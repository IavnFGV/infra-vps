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
            "Class": "os-pkgs",
            "Vulnerabilities": [
                {
                    "VulnerabilityID": "CVE-2026-0001",
                    "PkgName": "libssl3",
                    "InstalledVersion": "3.0.1",
                    "FixedVersion": "3.0.2",
                    "Severity": "CRITICAL",
                    "SeveritySource": "debian",
                    "CVSS": {"nvd": {"V3Vector": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"}},
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

CONTAINERS_JSON = json.dumps([
    {"Name": "/tts-1", "Config": {"Labels": {
        "com.docker.compose.project": "tts-service", "com.docker.compose.service": "tts",
        "com.docker.compose.project.working_dir": "/opt/dockge/stacks/tts-service",
        "infra-vps.fix": "github-workflow", "infra-vps.fix.repo": "owner/tts-service"}}},
    {"Name": "/infra-vps-nginx-1", "Config": {"Labels": {
        "com.docker.compose.project": "infra-vps", "com.docker.compose.service": "nginx",
        "com.docker.compose.project.working_dir": "/workspaces/infra-vps"}}},
    {"Name": "/bot-app-1", "Config": {"Labels": {
        "com.docker.compose.project": "bot", "com.docker.compose.service": "app",
        "com.docker.compose.project.working_dir": "/opt/dockge/stacks/bot",
        "infra-vps.fix": "compose-pull"}}},
])

FAKE_DOCKER = """#!/usr/bin/env bash
# containers: id -> "imageId<TAB>ref<TAB>project<TAB>service<TAB>/name"
case "$1" in
  ps) printf 'c1\\nc2\\nc3\\n' ;;
  version) echo linux/amd64 ;;
  inspect)
    if [[ "$2" != --format ]]; then cat "$CONTAINERS_FIXTURE"; exit 0; fi
    shift 3
    for c in "$@"; do
      case "$c" in
        c1) printf 'sha256:aaaaaaaaaaaaaaaa\\ttts-service-tts\\ttts-service\\ttts\\t/tts-1\\n' ;;
        c2) printf 'sha256:bbbbbbbbbbbbbbbb\\tnginx:1.30.7-alpine\\tinfra-vps\\tnginx\\t/infra-vps-nginx-1\\t\\n' ;;
        # containerd image store: .Image is the index, manifest digest differs
        c3) printf 'sha256:index000000000000\\tbot-app\\tbot\\tapp\\t/bot-app-1\\tsha256:manifest00000000\\n' ;;
      esac
    done ;;
  image)
    if [[ "$*" == *com.docker.compose.project* ]]; then
      # only the tts image is built by compose; the others are pulled
      [[ "${@: -1}" == tts-service-tts ]] && echo tts-service || echo '<no value>'
      exit 0
    fi
    case "${@: -1}" in
      tts-service-tts) echo "${TTS_TAG_ID:-sha256:aaaaaaaaaaaaaaaa}" ;;
      bot-app) if [[ "$*" == *--platform* ]]; then echo sha256:manifest00000000; else echo sha256:otherindex000000; fi ;;
      nginx:1.30.7-alpine) echo sha256:bbbbbbbbbbbbbbbb ;;
      *) exit 1 ;;
    esac ;;
  save) printf '%s\\n' "$*" >> "$DOCKER_SAVES"; touch "$3" ;;
esac
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
        notify.write_text('#!/usr/bin/env bash\ncat >> "$NOTIFY_OUT"\n'
                          '[[ -s "${NOTIFY_REPLY_MARKUP_FILE:-}" ]] && cp "$NOTIFY_REPLY_MARKUP_FILE" "$NOTIFY_OUT.markup"\n'
                          'exit 0\n')
        notify.chmod(0o755)
        fixture = self.root / "vuln.json"
        fixture.write_text(json.dumps(VULN_JSON))
        containers = self.root / "containers.json"
        containers.write_text(CONTAINERS_JSON)
        uu_log = self.root / "uu.log"
        uu_log.write_text(
            "2000-01-01 03:30:00,000 INFO Packages that will be upgraded: old-pkg\n"
        )
        self.env = {
            **os.environ,
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
            "TRIVY_CALLS": str(self.root / "trivy-calls"),
            "TRIVY_FIXTURE": str(fixture),
            "CONTAINERS_FIXTURE": str(containers),
            "NOTIFY_BIN": str(notify),
            "NOTIFY_OUT": str(self.root / "notify-out"),
            "REPORT_DIR": str(self.root / "reports"),
            "TRIVY_CACHE_DIR": str(self.root / "cache"),
            "UU_LOG": str(uu_log),
            "REBOOT_REQUIRED_FILE": str(self.root / "no-reboot"),
            "HEARTBEAT_WEEKDAY": "",
            "DOCKER_SAVES": str(self.root / "docker-saves"),
            "NOTIFY_CONFIG_FILE": str(self.root / "notify.env"),  # no GITHUB_FIX_TOKEN
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
        self.assertIn("New fixable vulnerabilities: 4", sent)  # host + 3 images
        self.assertNotIn("outdated image", sent)  # containerd store: manifest matches
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
        self.assertIn("Weekly status: 4 fixable", sent)

    def test_resolved_findings_are_reported(self):
        self.run_report()
        (self.root / "vuln.json").write_text(json.dumps({"Results": []}))
        _, sent = self.run_report()
        self.assertIn("Resolved since last scan: 4", sent)
        self.assertIn("tts-service/tts: libssl3 was 3.0.1, fixed in 3.0.2", sent)
        report = (self.root / "reports" / "latest.txt").read_text()
        self.assertIn("libssl3 was 3.0.1, fixed in 3.0.2", report)


    def test_counts_fix_routes_and_network_critical(self):
        fixture = {"Results": [
            {"Class": "os-pkgs", "Vulnerabilities": [
                {"VulnerabilityID": f"CVE-2026-10{n}", "PkgName": pkg, "InstalledVersion": "1",
                 "FixedVersion": "2", "Severity": "HIGH"}
                for n in range(3) for pkg in ("libkrb5-3", "libk5crypto3")
            ] + [
                {"VulnerabilityID": "CVE-2026-0001", "PkgName": "libssl3", "InstalledVersion": "1",
                 "FixedVersion": "2", "Severity": "CRITICAL",
                 "CVSS": {"redhat": {"V3Vector": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"}}},
            ]},
            {"Class": "lang-pkgs", "Vulnerabilities": [
                {"VulnerabilityID": "CVE-2026-0009", "PkgName": "requests", "InstalledVersion": "1",
                 "FixedVersion": "2", "Severity": "CRITICAL",
                 "CVSS": {"nvd": {"V3Vector": "CVSS:3.1/AV:L/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"}}},
            ]},
        ]}
        (self.root / "vuln.json").write_text(json.dumps(fixture))
        self.env["SCAN_HOST"] = "false"
        _, sent = self.run_report()
        # 3 images x 8 findings; 5 CVEs and 4 packages per image
        self.assertIn("New fixable vulnerabilities: 24 (5 unique CVE, 12 packages)", sent)
        # tts is built locally: OS -> rebuild, lang -> deps; nginx and bot are pulled
        self.assertIn("♻️ rebuild image 7, 🛠 deps/Dockerfile change 1, 📥 new upstream image 16", sent)
        self.assertIn("🚨 CRITICAL: 6 (🌐 network-exploitable: 3)", sent)
        self.assertIn("CVE-2026-0001        bot/app: libssl3 1 -> 2 🌐", sent)
        self.assertNotIn("requests 1 -> 2 🌐", sent)
        self.assertIn("HIGH     tts-service/tts: libkrb5-3 1 -> 2 (3 CVE)", sent)
        # network-exploitable CRITICAL are listed before the local ones
        self.assertLess(sent.index("libssl3"), sent.index("requests"))
        report = (self.root / "reports" / "latest.txt").read_text()
        self.assertIn("tts-service/tts: CRITICAL 2, HIGH 6; 5 unique CVE, 4 packages", report)

        self.env["HEARTBEAT_WEEKDAY"] = subprocess.check_output(["date", "+%u"], text=True).strip()
        _, sent = self.run_report()
        self.assertIn("Weekly status: 24 fixable HIGH/CRITICAL open (5 unique CVE, 12 packages)", sent)
        self.assertIn("- tts-service/tts: 8, CRITICAL 2 (🌐 1); ♻️ rebuild image 7, 🛠 deps/Dockerfile change 1", sent)


    def test_fix_proposals_and_buttons(self):
        self.env["SCAN_HOST"] = "false"
        _, sent = self.run_report()
        # bot/app opted in with compose-pull: its (upstream) finding gets a button
        self.assertIn("🔧 Auto-fix available:", sent)
        self.assertIn("- bot/app: docker compose pull + up in /opt/dockge/stacks/bot", sent)
        self.assertIn("restarts: bot-app-1", sent)
        # tts opted in with github-workflow, but no token: shown, no button
        self.assertIn("tts-service/tts: rebuild + redeploy: GitHub owner/tts-service deploy.yml", sent)
        self.assertIn("[needs GITHUB_FIX_TOKEN]", sent)
        # nginx has no infra-vps.fix label: no proposal
        self.assertNotIn("- infra-vps/nginx:", sent)
        markup = json.loads((self.root / "notify-out.markup").read_text())
        buttons = [row[0] for row in markup["inline_keyboard"]]
        self.assertEqual([b["text"] for b in buttons], ["🔧 Fix bot/app (1)"])
        fixes = json.loads((self.root / "reports" / "fixes.json").read_text())
        fix_id = buttons[0]["callback_data"].removeprefix("fix:")
        self.assertEqual(fixes["proposals"][fix_id]["action"],
                         {"type": "compose-pull", "working_dir": "/opt/dockge/stacks/bot",
                          "project": "bot"})

        # with a GitHub token the tts fix gets its button too
        (self.root / "notify.env").write_text("GITHUB_FIX_TOKEN=enc:x\n")
        (self.root / "reports" / "state.json").unlink()
        _, with_token = self.run_report()
        markup = json.loads((self.root / "notify-out.markup").read_text())
        self.assertIn("🔧 Fix tts-service/tts (1)", [row[0]["text"] for row in markup["inline_keyboard"]])
        self.assertNotIn("[needs GITHUB_FIX_TOKEN]", with_token)

    def test_host_fix_is_apt_upgrade_of_its_packages(self):
        _, sent = self.run_report()
        self.assertIn("- host: apt-get install --only-upgrade (1 packages) -> fixes 1 of 1", sent)
        self.env["HOST_AUTOFIX"] = "none"
        (self.root / "reports" / "state.json").unlink()
        _, sent = self.run_report()
        self.assertNotIn("- host: apt-get", sent)


class SecurityReportEdgeCaseTests(SecurityReportTests):
    def test_outdated_running_image_is_flagged_and_scanned_from_store(self):
        self.env["TTS_TAG_ID"] = "sha256:cccccccccccccccc"  # tag moved to a newer build
        _, sent = self.run_report()
        self.assertIn("tts-service/tts: container runs an outdated image", sent)
        self.assertIn("sha256:aaaaaaaaaaaaaaaa", (self.root / "docker-saves").read_text())
        self.assertIn("--input", (self.root / "trivy-calls").read_text())
        self.assertIn("tts-service/tts: libssl3", sent)

    def test_packages_of_non_running_kernels_are_ignored(self):
        fixture = {"Results": [{"Vulnerabilities": [
            {"VulnerabilityID": "CVE-1", "PkgName": "linux-modules-0.0.0-1-generic",
             "InstalledVersion": "0.0.0-1.1", "FixedVersion": "0.0.0-2.2", "Severity": "HIGH"},
        ]}]}
        (self.root / "vuln.json").write_text(json.dumps(fixture))
        _, sent = self.run_report()
        self.assertNotIn("host: linux-modules", sent)
        self.assertIn("infra-vps/nginx: linux-modules", sent)  # images are not filtered


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
