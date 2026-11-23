#!/usr/bin/env python3
"""Telegram buttons for security-report auto-fixes. Stdlib only.

scheduled-tasks/security-report.sh classifies findings and stores one
proposal per fixable component in <REPORT_DIR>/fixes.json; the Telegram
message carries a "🔧 Fix ..." button per proposal. This bot long-polls
Telegram (outbound only, no webhook), and on a button press:

  1. checks that it came from the configured chat and an allowed user,
  2. asks for confirmation (what runs, what restarts),
  3. runs the proposal's action — only actions defined in EXECUTORS below,
     with parameters taken from fixes.json, never from the button,
  4. reports the result and rescans (security-report.sh), so the next
     message shows what got resolved.

Adding a new kind of fix = one function in EXECUTORS + its rule in
security-report-summarize.py (FIX_ACTIONS / plan_fixes).

Usage:
  security-fix-bot.py            run forever (systemd: infra-vps-security-fix-bot)
  security-fix-bot.py --once     process one batch of updates and exit (tests)
  security-fix-bot.py run <id>   run a proposal from the shell, no Telegram

Config: the Telegram config of scripts/notify-telegram.sh, plus
  TELEGRAM_ADMIN_IDS=<id>[,<id>]  who may press (default: TELEGRAM_CHAT_ID,
                                  i.e. you in a private chat with the bot)
  GITHUB_FIX_TOKEN=enc:...        fine-grained PAT, Actions: read & write,
                                  for github-workflow fixes
"""

from __future__ import annotations

import datetime as dt
import fcntl
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
STATE_DIR = Path(os.environ.get("REPORT_DIR", "/var/log/infra-vps-security"))
FIXES_FILE = STATE_DIR / "fixes.json"
OFFSET_FILE = STATE_DIR / "fix-bot.offset"
LOCK_FILE = STATE_DIR / "fix-bot.lock"
LOG_FILE = STATE_DIR / "fixes.log"
TELEGRAM_API_URL = os.environ.get("TELEGRAM_API_URL", "https://api.telegram.org")
GITHUB_API_URL = os.environ.get("GITHUB_API_URL", "https://api.github.com")
GITHUB_POLL_SECONDS = float(os.environ.get("GITHUB_POLL_SECONDS", "15"))
GITHUB_TIMEOUT_SECONDS = float(os.environ.get("GITHUB_TIMEOUT_SECONDS", "1800"))
REPORT_BIN = os.environ.get("SECURITY_REPORT_BIN",
                            str(REPO_ROOT / "scheduled-tasks" / "security-report.sh"))
DECRYPT_BIN = os.environ.get("DECRYPT_SCRIPT", str(REPO_ROOT / "scripts" / "decrypt-value.sh"))
CMD_TIMEOUT = 1800
APT_PKG = re.compile(r"[a-z0-9][a-z0-9+.-]*(:[a-z0-9]+)?")


def log(text: str) -> None:
    line = f"{dt.datetime.now(dt.timezone.utc):%Y-%m-%dT%H:%M:%SZ} [fix-bot] {text}"
    print(line, flush=True)
    try:
        with LOG_FILE.open("a") as fh:
            fh.write(line + "\n")
    except OSError:
        pass


# ---- config ------------------------------------------------------------------

def load_config() -> dict[str, str]:
    if os.environ.get("NOTIFY_CONFIG_FILE"):
        files = [Path(os.environ["NOTIFY_CONFIG_FILE"])]
    else:
        files = [REPO_ROOT / "config" / "notify.env", Path("/etc/infra-vps/notify.env")]
    raw: dict[str, str] = {}
    for path in files:
        if not path.is_file():
            continue
        for line in path.read_text().splitlines():
            key, sep, value = line.strip().partition("=")
            if sep and key and not key.startswith("#"):
                raw[key.strip()] = value.strip().strip("'\"")
    config = {}
    for key, value in raw.items():
        if value.startswith("enc:"):
            value = subprocess.run([DECRYPT_BIN, value], check=True, text=True,
                                   capture_output=True).stdout.strip()
        config[key] = value
    return config


# ---- fixes.json --------------------------------------------------------------

def load_fixes() -> dict:
    try:
        return json.loads(FIXES_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return {"proposals": {}}


def save_fixes(fixes: dict) -> None:
    tmp = FIXES_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(fixes, indent=1))
    tmp.replace(FIXES_FILE)


def set_status(fix_id: str, status: str) -> None:
    fixes = load_fixes()
    if fix_id in fixes.get("proposals", {}):
        fixes["proposals"][fix_id]["status"] = status
        save_fixes(fixes)


def get_proposal(fix_id: str) -> dict | None:
    fixes = load_fixes()
    proposal = fixes.get("proposals", {}).get(fix_id)
    expires = fixes.get("expires")
    if not proposal or (expires and dt.datetime.fromisoformat(expires) < dt.datetime.now()):
        return None
    return proposal


# ---- executors -----------------------------------------------------------------

def run_cmd(cmd: list[str], cwd: str | None = None, env: dict | None = None) -> tuple[bool, str]:
    log(f"$ {' '.join(cmd)}" + (f"  (in {cwd})" if cwd else ""))
    try:
        result = subprocess.run(cmd, cwd=cwd, env={**os.environ, **(env or {})}, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=CMD_TIMEOUT, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, f"$ {' '.join(cmd)}\n{exc}"
    return result.returncode == 0, f"$ {' '.join(cmd)}\n{result.stdout}"


def run_steps(steps, cwd=None, env=None) -> tuple[bool, str]:
    output = []
    for cmd in steps:
        ok, out = run_cmd(cmd, cwd=cwd, env=env)
        output.append(out)
        if not ok:
            return False, "\n".join(output)
    return True, "\n".join(output)


def compose_dir(action) -> str:
    working_dir = Path(action.get("working_dir", ""))
    if not working_dir.is_absolute() or not working_dir.is_dir():
        raise ValueError(f"compose working dir not found: {working_dir}")
    return str(working_dir)


def compose_base(action) -> list[str]:
    base = ["docker", "compose"]
    if action.get("project"):
        base += ["-p", action["project"]]
    return base


def fix_compose_rebuild(action, config) -> tuple[bool, str]:
    base = compose_base(action)
    return run_steps([base + ["build", "--pull"],
                      base + ["up", "-d", "--wait", "--wait-timeout", "180"]],
                     cwd=compose_dir(action))


def fix_compose_pull(action, config) -> tuple[bool, str]:
    base = compose_base(action)
    return run_steps([base + ["pull"],
                      base + ["up", "-d", "--wait", "--wait-timeout", "180"]],
                     cwd=compose_dir(action))


def fix_apt_upgrade(action, config) -> tuple[bool, str]:
    packages = action.get("packages") or []
    if not packages or not all(APT_PKG.fullmatch(p) for p in packages):
        raise ValueError(f"bad package list: {packages}")
    env = {"DEBIAN_FRONTEND": "noninteractive", "NEEDRESTART_MODE": "a"}
    return run_steps([["apt-get", "update"],
                      ["apt-get", "install", "-y", "--only-upgrade",
                       "-o", "Dpkg::Options::=--force-confold", *packages]], env=env)


def github(method: str, path: str, token: str, body: dict | None = None):
    request = urllib.request.Request(
        f"{GITHUB_API_URL}{path}", method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {token}",
                 "Accept": "application/vnd.github+json",
                 "X-GitHub-Api-Version": "2022-11-28",
                 "Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        data = response.read()
    return json.loads(data) if data else {}


def fix_github_workflow(action, config) -> tuple[bool, str]:
    token = config.get("GITHUB_FIX_TOKEN", "")
    repo, workflow, ref = action.get("repo", ""), action.get("workflow", ""), action.get("ref", "main")
    if not token:
        raise ValueError("GITHUB_FIX_TOKEN is not configured")
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", repo) or not re.fullmatch(r"[\w.-]+\.ya?ml", workflow):
        raise ValueError(f"bad repo/workflow: {repo} {workflow}")
    runs_path = f"/repos/{repo}/actions/workflows/{workflow}/runs?event=workflow_dispatch&per_page=10"
    known = {r["id"] for r in github("GET", runs_path, token).get("workflow_runs", [])}
    github("POST", f"/repos/{repo}/actions/workflows/{workflow}/dispatches", token, {"ref": ref})
    log(f"dispatched {repo} {workflow}@{ref}")
    deadline = time.monotonic() + GITHUB_TIMEOUT_SECONDS
    run_id = None
    while time.monotonic() < deadline:
        time.sleep(GITHUB_POLL_SECONDS)
        if run_id is None:
            fresh = [r for r in github("GET", runs_path, token).get("workflow_runs", [])
                     if r["id"] not in known]
            if not fresh:
                continue
            run_id = min(r["id"] for r in fresh)
        run = github("GET", f"/repos/{repo}/actions/runs/{run_id}", token)
        if run.get("status") == "completed":
            conclusion = run.get("conclusion")
            return conclusion == "success", f"GitHub run {conclusion}: {run.get('html_url', '')}"
    return False, f"GitHub run did not finish in {GITHUB_TIMEOUT_SECONDS:.0f}s" + (
        f": {GITHUB_API_URL}/repos/{repo}/actions/runs/{run_id}" if run_id else " (run not found)")


EXECUTORS = {
    "github-workflow": fix_github_workflow,
    "compose-rebuild": fix_compose_rebuild,
    "compose-pull": fix_compose_pull,
    "apt-upgrade": fix_apt_upgrade,
}


def describe(proposal) -> str:
    action = proposal["action"]
    what = {
        "github-workflow": f"GitHub Actions {action.get('repo')} {action.get('workflow')} "
                           f"(тесты, пересборка, деплой)",
        "compose-rebuild": f"docker compose build --pull && up -d в {action.get('working_dir')}",
        "compose-pull": f"docker compose pull && up -d в {action.get('working_dir')}",
        "apt-upgrade": "apt-get install --only-upgrade " + " ".join(action.get("packages", [])),
    }.get(action["type"], action["type"])
    return (f"{proposal['label']}: {what}\n"
            f"Закроет: {proposal['fixes']} из {proposal['total']} находок\n"
            f"Будут перезапущены: {', '.join(proposal['restarts'])}")


def execute(proposal, config) -> tuple[bool, str]:
    executor = EXECUTORS.get(proposal["action"]["type"])
    if not executor:
        return False, f"unknown fix type {proposal['action']['type']}"
    try:
        return executor(proposal["action"], config)
    except (ValueError, OSError, urllib.error.URLError, KeyError) as exc:
        return False, f"{type(exc).__name__}: {exc}"


def rescan() -> None:
    log("rescanning")
    try:
        subprocess.run(["bash", REPORT_BIN], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=CMD_TIMEOUT)
    except (OSError, subprocess.TimeoutExpired) as exc:
        log(f"rescan failed: {exc}")


# ---- Telegram ------------------------------------------------------------------

class Telegram:
    def __init__(self, token: str):
        self.base = f"{TELEGRAM_API_URL}/bot{token}"

    def call(self, method: str, http_timeout: float = 30, **params):
        data = urllib.parse.urlencode({
            key: json.dumps(value) if isinstance(value, (dict, list)) else value
            for key, value in params.items() if value is not None}).encode()
        with urllib.request.urlopen(f"{self.base}/{method}", data=data, timeout=http_timeout) as resp:
            return json.loads(resp.read() or b"{}")


def tail(text: str, limit: int = 3000) -> str:
    return text if len(text) <= limit else "...\n" + text[-limit:]


def handle_callback(tg: Telegram, config: dict, callback: dict) -> None:
    data = callback.get("data") or ""
    user = str((callback.get("from") or {}).get("id", ""))
    message = callback.get("message") or {}
    chat = str((message.get("chat") or {}).get("id", ""))
    admins = {a.strip() for a in (config.get("TELEGRAM_ADMIN_IDS")
                                  or config.get("TELEGRAM_CHAT_ID", "")).split(",") if a.strip()}

    def answer(text: str) -> None:
        tg.call("answerCallbackQuery", callback_query_id=callback.get("id"), text=text)

    if chat != config.get("TELEGRAM_CHAT_ID") or user not in admins:
        log(f"rejected {data!r} from user {user} in chat {chat}")
        answer("Нет доступа")
        return
    kind, _, fix_id = data.partition(":")
    proposal = get_proposal(fix_id)
    if proposal is None:
        answer("Кнопка устарела — дождитесь нового отчёта")
        return

    if kind == "fix":
        answer("")
        tg.call("sendMessage", chat_id=chat, reply_to_message_id=message.get("message_id"),
                text=f"Запустить автофикс?\n{describe(proposal)}",
                reply_markup={"inline_keyboard": [[
                    {"text": "✅ Запустить", "callback_data": f"run:{fix_id}"},
                    {"text": "Отмена", "callback_data": f"cancel:{fix_id}"}]]})
    elif kind == "cancel":
        answer("Отменено")
        tg.call("editMessageText", chat_id=chat, message_id=message.get("message_id"),
                text=f"Отменено.\n{describe(proposal)}")
    elif kind == "run":
        if proposal.get("status") in ("running", "done"):
            answer(f"Уже {proposal['status']}")
            return
        set_status(fix_id, "running")
        answer("Запущено")
        tg.call("editMessageText", chat_id=chat, message_id=message.get("message_id"),
                text=f"⏳ Выполняется…\n{describe(proposal)}")
        log(f"run {fix_id} by user {user}: {json.dumps(proposal['action'])}")
        ok, output = execute(proposal, config)
        set_status(fix_id, "done" if ok else "failed")
        log(f"{fix_id} {'done' if ok else 'FAILED'}\n{output}")
        tg.call("sendMessage", chat_id=chat,
                text=f"{'✅ Готово' if ok else '❌ Не удалось'}: {proposal['label']}\n"
                     f"{tail(output)}" + ("\nПересканирую, отчёт придёт следующим сообщением."
                                          if ok else ""))
        if ok:
            rescan()
    else:
        answer("?")


def poll(tg: Telegram, config: dict, once: bool) -> None:
    try:
        offset = int(OFFSET_FILE.read_text())
    except (OSError, ValueError):
        offset = 0
    while True:
        try:
            updates = tg.call("getUpdates", http_timeout=70, offset=offset,
                              timeout=0 if once else 50,
                              allowed_updates=["callback_query"]).get("result", [])
        except (urllib.error.URLError, OSError, json.JSONDecodeError) as exc:
            log(f"getUpdates failed: {exc}")
            if once:
                return
            time.sleep(10)
            continue
        for update in updates:
            offset = max(offset, update["update_id"] + 1)
            OFFSET_FILE.write_text(str(offset))
            if "callback_query" in update:
                try:
                    handle_callback(tg, config, update["callback_query"])
                except (urllib.error.URLError, OSError) as exc:
                    log(f"callback failed: {exc}")
        if once:
            return


def main(argv: list[str]) -> int:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    config = load_config()
    if len(argv) == 2 and argv[0] == "run":
        proposal = get_proposal(argv[1])
        if not proposal:
            print(f"no such (or expired) proposal: {argv[1]}", file=sys.stderr)
            return 1
        print(describe(proposal))
        ok, output = execute(proposal, config)
        print(output)
        set_status(argv[1], "done" if ok else "failed")
        return 0 if ok else 1
    if not config.get("TELEGRAM_BOT_TOKEN") or not config.get("TELEGRAM_CHAT_ID"):
        log("Telegram is not configured; nothing to do")
        return 0 if "--once" in argv else 1
    lock = LOCK_FILE.open("w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        log("another fix bot is running")
        return 1
    # A fix that was running when the bot stopped can be pressed again.
    fixes = load_fixes()
    if any(p.get("status") == "running" for p in fixes.get("proposals", {}).values()):
        for proposal in fixes["proposals"].values():
            if proposal.get("status") == "running":
                proposal["status"] = "interrupted"
        save_fixes(fixes)
    poll(Telegram(config["TELEGRAM_BOT_TOKEN"]), config, once="--once" in argv)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
