import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest
import urllib.parse


ROOT = Path(__file__).resolve().parents[1]
BOT = ROOT / "scripts" / "security-fix-bot.py"


class FakeApi:
    """Telegram + GitHub API on localhost; records every request."""

    def __init__(self):
        self.requests = []
        self.updates = []
        self.github_runs = []          # list returned by .../runs
        self.run_after_dispatch = None  # run that appears once dispatched
        api = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def reply(self, body, code=200):
                data = json.dumps(body).encode() if body is not None else b""
                self.send_response(code)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def do_GET(self):
                api.requests.append(("GET", self.path, None, dict(self.headers)))
                if self.path.endswith("/runs?event=workflow_dispatch&per_page=10"):
                    self.reply({"workflow_runs": api.github_runs})
                elif "/actions/runs/" in self.path:
                    self.reply(api.run_after_dispatch)
                else:
                    self.reply({}, 404)

            def do_POST(self):
                length = int(self.headers.get("Content-Length") or 0)
                body = self.rfile.read(length).decode()
                api.requests.append(("POST", self.path, body, dict(self.headers)))
                if self.path.endswith("/getUpdates"):
                    updates, api.updates = api.updates, []
                    self.reply({"ok": True, "result": updates})
                elif self.path.endswith("/dispatches"):
                    if api.run_after_dispatch:
                        api.github_runs = [*api.github_runs, api.run_after_dispatch]
                    self.reply(None, 204)
                else:
                    self.reply({"ok": True, "result": {}})

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def telegram_calls(self, method):
        return [dict(urllib.parse.parse_qsl(body)) for verb, path, body, _ in self.requests
                if verb == "POST" and path.endswith(f"/{method}")]

    def close(self):
        self.server.shutdown()


class FixBotTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.api = FakeApi()
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        docker = bin_dir / "docker"
        docker.write_text('#!/usr/bin/env bash\nprintf "%s | %s\\n" "$PWD" "$*" >> "$DOCKER_CALLS"\n')
        docker.chmod(0o755)
        report = self.root / "report.sh"
        report.write_text('echo rescan >> "$DOCKER_CALLS"\n')
        (self.root / "stack").mkdir()
        config = self.root / "notify.env"
        config.write_text("TELEGRAM_BOT_TOKEN=T\nTELEGRAM_CHAT_ID=100\nGITHUB_FIX_TOKEN=GH\n")
        self.reports = self.root / "reports"
        self.reports.mkdir()
        self.env = {
            **os.environ,
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
            "REPORT_DIR": str(self.reports),
            "NOTIFY_CONFIG_FILE": str(config),
            "TELEGRAM_API_URL": self.api.url,
            "GITHUB_API_URL": self.api.url,
            "GITHUB_POLL_SECONDS": "0",
            "SECURITY_REPORT_BIN": str(report),
            "DOCKER_CALLS": str(self.root / "docker-calls"),
        }

    def tearDown(self):
        self.api.close()
        self.tmp.cleanup()

    def write_fixes(self, action, expires="2999-01-01T00:00:00"):
        (self.reports / "fixes.json").write_text(json.dumps({"expires": expires, "proposals": {
            "abcd1234": {"id": "abcd1234", "label": "bot/app", "action": action, "fixes": 3,
                         "total": 4, "restarts": ["bot-app-1"], "blocked": "", "status": "pending"}}}))

    def press(self, data, user=100, chat=100):
        self.api.updates.append({"update_id": len(self.api.requests) + 1, "callback_query": {
            "id": "cb", "data": data, "from": {"id": user},
            "message": {"message_id": 7, "chat": {"id": chat}}}})
        result = subprocess.run(["python3", "-I", str(BOT), "--once"], env=self.env,
                                text=True, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)

    def docker_calls(self):
        path = self.root / "docker-calls"
        return path.read_text() if path.exists() else ""

    def status(self):
        return json.loads((self.reports / "fixes.json").read_text())["proposals"]["abcd1234"]["status"]

    def test_fix_asks_confirmation_then_runs_and_rescans(self):
        self.write_fixes({"type": "compose-rebuild", "working_dir": str(self.root / "stack"),
                          "project": "bot"})
        self.press("fix:abcd1234")
        confirm = self.api.telegram_calls("sendMessage")[-1]
        self.assertIn("Будут перезапущены: bot-app-1", confirm["text"])
        self.assertIn("run:abcd1234", confirm["reply_markup"])
        self.assertEqual(self.docker_calls(), "")  # nothing runs before confirmation

        self.press("run:abcd1234")
        calls = self.docker_calls()
        self.assertIn(f"{self.root / 'stack'} | compose -p bot build --pull", calls)
        self.assertIn("compose -p bot up -d --wait", calls)
        self.assertTrue(calls.endswith("rescan\n"))
        self.assertEqual(self.status(), "done")
        self.assertIn("✅ Готово: bot/app", self.api.telegram_calls("sendMessage")[-1]["text"])

        self.press("run:abcd1234")  # second press does not run it again
        self.assertEqual(self.docker_calls().count("build --pull"), 1)

    def test_other_users_and_chats_are_rejected(self):
        self.write_fixes({"type": "compose-pull", "working_dir": str(self.root / "stack")})
        self.press("run:abcd1234", user=666)
        self.press("run:abcd1234", user=100, chat=666)
        self.assertEqual(self.docker_calls(), "")
        self.assertEqual(self.status(), "pending")
        answers = self.api.telegram_calls("answerCallbackQuery")
        self.assertEqual([a["text"] for a in answers], ["Нет доступа", "Нет доступа"])

    def test_expired_or_unknown_buttons_do_nothing(self):
        self.write_fixes({"type": "compose-pull", "working_dir": str(self.root / "stack")},
                         expires="2000-01-01T00:00:00")
        self.press("run:abcd1234")
        self.press("run:ffffffff")
        self.assertEqual(self.docker_calls(), "")
        self.assertIn("устарела", self.api.telegram_calls("answerCallbackQuery")[0]["text"])

    def test_github_workflow_dispatches_and_waits_for_the_run(self):
        self.write_fixes({"type": "github-workflow", "repo": "owner/svc",
                          "workflow": "deploy.yml", "ref": "main"})
        self.api.github_runs = [{"id": 1}]  # older run, must not be picked
        self.api.run_after_dispatch = {"id": 2, "status": "completed", "conclusion": "success",
                                       "html_url": "https://github.example/run/2"}
        self.press("run:abcd1234")
        posts = [(path, body, headers) for verb, path, body, headers in self.api.requests
                 if verb == "POST" and path.endswith("/dispatches")]
        self.assertEqual(posts[0][0], "/repos/owner/svc/actions/workflows/deploy.yml/dispatches")
        self.assertEqual(json.loads(posts[0][1]), {"ref": "main"})
        self.assertEqual(posts[0][2]["Authorization"], "Bearer GH")
        self.assertIn("https://github.example/run/2", self.api.telegram_calls("sendMessage")[-1]["text"])
        self.assertEqual(self.status(), "done")

    def test_failed_workflow_is_reported_and_not_rescanned(self):
        self.write_fixes({"type": "github-workflow", "repo": "owner/svc",
                          "workflow": "deploy.yml", "ref": "main"})
        self.api.run_after_dispatch = {"id": 5, "status": "completed", "conclusion": "failure",
                                       "html_url": "u"}
        self.press("run:abcd1234")
        self.assertIn("❌ Не удалось", self.api.telegram_calls("sendMessage")[-1]["text"])
        self.assertEqual(self.status(), "failed")
        self.assertNotIn("rescan", self.docker_calls())

    def test_bad_apt_package_names_are_refused(self):
        self.write_fixes({"type": "apt-upgrade", "packages": ["openssl", "x; rm -rf /"]})
        self.press("run:abcd1234")
        self.assertIn("bad package list", self.api.telegram_calls("sendMessage")[-1]["text"])
        self.assertEqual(self.status(), "failed")


if __name__ == "__main__":
    unittest.main()
