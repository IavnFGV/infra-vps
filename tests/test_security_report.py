import json
import os
import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]

VULN_JSON = {
    "Results": [
        {
            "Target": "debian",
            "Vulnerabilities": [
                {
                    "VulnerabilityID": "CVE-2026-0001",
                    "PkgName": "libssl3",
                    "InstalledVersion": "3.0.1",
                    "FixedVersion": "3.0.2",
                    "Severity": "CRITICAL",
                },
                {
                    "VulnerabilityID": "CVE-2026-0002",
                    "PkgName": "zlib",
                    "InstalledVersion": "1.2",
                    "FixedVersion": "",
                    "Severity": "HIGH",
                },
            ],
        }
    ]
}

FAKE_TRIVY = """#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$TRIVY_CALLS"
out=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--output" ]]; then out="$2"; shift; fi
  shift
done
[[ -n "$out" ]] && cp "$TRIVY_FIXTURE" "$out"
exit 0
"""

FAKE_DOCKER = """#!/usr/bin/env bash
printf 'tts-service-tts\\ttts-service\\ttts\\ttts-1\\n'
printf 'nginx:1.30.7-alpine\\tinfra-vps\\tnginx\\tinfra-vps-nginx-1\\n'
"""


class SecurityReportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        for name, body in (("trivy", FAKE_TRIVY), ("docker", FAKE_DOCKER)):
            path = bin_dir / name
            path.write_text(body)
            path.chmod(0o755)
        notify = self.root / "notify"
        notify.write_text('#!/usr/bin/env bash\ncat >> "$NOTIFY_OUT"\n')
        notify.chmod(0o755)
        fixture = self.root / "vuln.json"
        fixture.write_text(json.dumps(VULN_JSON))
        uu_log = self.root / "uu.log"
        uu_log.write_text(
            "2000-01-01 03:30:00,000 INFO Packages that will be upgraded: old-pkg\n"
        )
        self.env = {
            **os.environ,
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
            "TRIVY_CALLS": str(self.root / "trivy-calls"),
            "TRIVY_FIXTURE": str(fixture),
            "NOTIFY_BIN": str(notify),
            "NOTIFY_OUT": str(self.root / "notify-out"),
            "REPORT_DIR": str(self.root / "reports"),
            "TRIVY_CACHE_DIR": str(self.root / "cache"),
            "UU_LOG": str(uu_log),
            "REBOOT_REQUIRED_FILE": str(self.root / "no-reboot"),
            "HEARTBEAT_WEEKDAY": "",
        }

    def tearDown(self):
        self.tmp.cleanup()

    def run_report(self):
        result = subprocess.run(
            ["bash", str(ROOT / "scheduled-tasks" / "security-report.sh")],
            text=True,
            capture_output=True,
            env=self.env,
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        out = self.root / "notify-out"
        sent = out.read_text() if out.exists() else ""
        if out.exists():
            out.unlink()
        return result, sent

    def test_first_run_notifies_new_fixable_findings_only(self):
        result, sent = self.run_report()
        self.assertIn("New fixable vulnerabilities: 3", sent)  # host + 2 images
        self.assertIn("CVE-2026-0001", sent)
        self.assertNotIn("CVE-2026-0002", sent)  # no fix available -> ignored
        self.assertIn("tts-service/tts", sent)
        self.assertIn("infra-vps/nginx", sent)
        self.assertNotIn("old-pkg", sent)  # outside the 24h window
        self.assertTrue((self.root / "reports" / "latest.txt").is_file())
        calls = (self.root / "trivy-calls").read_text()
        self.assertIn("--ignore-unfixed", calls)
        self.assertIn("rootfs", calls)

    def test_second_run_without_changes_is_silent(self):
        self.run_report()
        result, sent = self.run_report()
        self.assertEqual(sent, "")
        self.assertIn("Nothing new", result.stdout)

    def test_heartbeat_reports_even_without_news(self):
        self.run_report()
        self.env["HEARTBEAT_WEEKDAY"] = subprocess.check_output(["date", "+%u"], text=True).strip()
        _, sent = self.run_report()
        self.assertIn("Weekly status: 3 fixable", sent)

    def test_resolved_findings_are_reported(self):
        self.run_report()
        (self.root / "vuln.json").write_text(json.dumps({"Results": []}))
        _, sent = self.run_report()
        self.assertIn("Resolved since last scan: 3", sent)


class NotifyTelegramTests(unittest.TestCase):
    def test_unconfigured_prints_message_and_succeeds(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [str(ROOT / "scripts" / "notify-telegram.sh"), "hello"],
                text=True,
                capture_output=True,
                env={**os.environ, "NOTIFY_CONFIG_FILE": f"{directory}/missing.env"},
            )
        self.assertEqual(result.returncode, 0)
        self.assertIn("hello", result.stdout)

    def test_token_is_not_passed_on_command_line(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "bin").mkdir()
            curl = root / "bin" / "curl"
            curl.write_text(
                '#!/usr/bin/env bash\n'
                'printf "%s\\n" "$*" > "$CURL_ARGS"\n'
                'while [[ $# -gt 0 ]]; do [[ "$1" == --config ]] && cat "$2" > "$CURL_CFG"; shift; done\n'
            )
            curl.chmod(0o755)
            config = root / "notify.env"
            config.write_text("TELEGRAM_BOT_TOKEN=SECRET123\nTELEGRAM_CHAT_ID=42\n")
            result = subprocess.run(
                [str(ROOT / "scripts" / "notify-telegram.sh")],
                input="alert",
                text=True,
                capture_output=True,
                env={
                    **os.environ,
                    "PATH": f"{root / 'bin'}:{os.environ['PATH']}",
                    "NOTIFY_CONFIG_FILE": str(config),
                    "CURL_ARGS": str(root / "args"),
                    "CURL_CFG": str(root / "cfg"),
                },
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            args = (root / "args").read_text()
            self.assertNotIn("SECRET123", args)
            self.assertIn("chat_id=42", args)
            self.assertIn("alert", args)
            self.assertIn("botSECRET123/sendMessage", (root / "cfg").read_text())

    def test_encrypted_config_from_repo_copy(self):
        """New server: repo clone + restored master key is enough."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / "repo"
            (repo / "scripts").mkdir(parents=True)
            (repo / "config").mkdir()
            for name in ("notify-telegram.sh", "decrypt-value.sh", "encrypt-value.sh"):
                shutil.copy2(ROOT / "scripts" / name, repo / "scripts" / name)
            key = root / "master.key"
            key.write_text("test-master-key\n")
            env = {**os.environ, "INFRA_MASTER_KEY_FILE": str(key)}
            encrypt = lambda v: subprocess.check_output(
                [str(repo / "scripts" / "encrypt-value.sh"), v], text=True, env=env
            ).strip()
            (repo / "config" / "notify.env").write_text(
                f"TELEGRAM_BOT_TOKEN={encrypt('TOKEN777')}\n"
                f"TELEGRAM_CHAT_ID={encrypt('99')}\n"
            )
            (root / "bin").mkdir()
            curl = root / "bin" / "curl"
            curl.write_text(
                '#!/usr/bin/env bash\n'
                'printf "%s\\n" "$*" > "$CURL_ARGS"\n'
                'while [[ $# -gt 0 ]]; do [[ "$1" == --config ]] && cat "$2" > "$CURL_CFG"; shift; done\n'
            )
            curl.chmod(0o755)
            result = subprocess.run(
                [str(repo / "scripts" / "notify-telegram.sh"), "moved"],
                text=True,
                capture_output=True,
                env={
                    **env,
                    "PATH": f"{root / 'bin'}:{os.environ['PATH']}",
                    "CURL_ARGS": str(root / "args"),
                    "CURL_CFG": str(root / "cfg"),
                },
            )
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn("chat_id=99", (root / "args").read_text())
            self.assertIn("botTOKEN777/sendMessage", (root / "cfg").read_text())


if __name__ == "__main__":
    unittest.main()
