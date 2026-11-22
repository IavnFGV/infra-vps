#!/usr/bin/env python3
"""Summarize Trivy JSON results + unattended-upgrades log into a report.

Used by scheduled-tasks/security-report.sh. Stdlib only.

Usage:
  security-report-summarize.py \
      --scan "<label>=<trivy.json>" [--scan ...] \
      --scan-error "<label>=<message>" [...] \
      --state <state.json> --report <report.txt> --message <message.txt> \
      [--uu-log /var/log/unattended-upgrades/unattended-upgrades.log] \
      [--since-hours 24] [--reboot-required-file /var/run/reboot-required] \
      [--heartbeat]

Writes the full report to --report, and a short Telegram message to
--message only when something is worth telling (new fixable vulnerabilities,
upgrades installed, upgrade errors, scan errors, pending reboot) or when
--heartbeat is given. The --message file is left empty otherwise.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
from pathlib import Path

SEVERITY_ORDER = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3, "UNKNOWN": 4}
UU_LINE = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}),\d+ (\w+) (.*)$")
MAX_LISTED = 15


def split_pair(value: str) -> tuple[str, str]:
    label, sep, rest = value.partition("=")
    if not sep or not label:
        raise argparse.ArgumentTypeError(f"expected <label>=<value>, got {value!r}")
    return label, rest


KERNEL_PKG = re.compile(r"^linux-[a-z0-9-]*?-(\d+\.\d+\.\d+-\d+)(?:-[a-z0-9]+)?$")


def is_idle_kernel(pkg: str, running_kernel: str | None) -> bool:
    """linux-modules-7.0.0-15-generic while 7.0.0-44-generic is running."""
    if not running_kernel:
        return False
    match = KERNEL_PKG.match(pkg)
    return bool(match) and not running_kernel.startswith(match.group(1) + "-") \
        and running_kernel != match.group(1)


def load_findings(scans: list[tuple[str, str]], errors: list[tuple[str, str]],
                  running_kernel: str | None = None):
    findings = {}
    for label, path in scans:
        try:
            data = json.loads(Path(path).read_text() or "{}")
        except (OSError, json.JSONDecodeError) as exc:
            errors.append((label, f"cannot read trivy output: {exc}"))
            continue
        for result in data.get("Results") or []:
            for vuln in result.get("Vulnerabilities") or []:
                if not vuln.get("FixedVersion"):
                    continue
                if label == "host" and is_idle_kernel(vuln.get("PkgName", ""), running_kernel):
                    continue
                key = f"{label}|{vuln.get('PkgName')}|{vuln.get('VulnerabilityID')}"
                findings[key] = {
                    "label": label,
                    "pkg": vuln.get("PkgName", "?"),
                    "installed": vuln.get("InstalledVersion", "?"),
                    "fixed": vuln.get("FixedVersion", "?"),
                    "id": vuln.get("VulnerabilityID", "?"),
                    "severity": vuln.get("Severity", "UNKNOWN"),
                    "title": (vuln.get("Title") or "").strip(),
                }
    return findings


def read_uu_log(path: Path, since: dt.datetime):
    upgraded, errors = [], []
    if not path.is_file():
        return upgraded, errors
    for line in path.read_text(errors="replace").splitlines():
        match = UU_LINE.match(line)
        if not match:
            continue
        stamp = dt.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S")
        if stamp < since:
            continue
        level, text = match.group(2), match.group(3)
        if text.startswith("Packages that will be upgraded:"):
            upgraded.extend(text.split(":", 1)[1].split())
        elif level in ("ERROR", "CRITICAL"):
            errors.append(text)
    return sorted(set(upgraded)), errors


def sort_key(item):
    return (SEVERITY_ORDER.get(item["severity"], 9), item["label"], item["pkg"], item["id"])


def fmt(item) -> str:
    return (f"{item['severity']:<8} {item['id']:<20} {item['label']}: "
            f"{item['pkg']} {item['installed']} -> {item['fixed']}")


def fmt_resolved(key: str, item) -> str:
    if not item:
        return f"{key.split('|')[2]:<20} {key.split('|')[0]}: {key.split('|')[1]}"
    return (f"{item['id']:<20} {item['label']}: {item['pkg']} "
            f"was {item['installed']}, fixed in {item['fixed']}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scan", action="append", type=split_pair, default=[])
    parser.add_argument("--scan-error", action="append", type=split_pair, default=[])
    parser.add_argument("--state", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--message", required=True, type=Path)
    parser.add_argument("--uu-log", type=Path,
                        default=Path("/var/log/unattended-upgrades/unattended-upgrades.log"))
    parser.add_argument("--since-hours", type=float, default=24)
    parser.add_argument("--reboot-required-file", type=Path,
                        default=Path("/var/run/reboot-required"))
    parser.add_argument("--heartbeat", action="store_true")
    parser.add_argument("--running-kernel", help="uname -r; host packages of other kernels are ignored")
    parser.add_argument("--now", help="override current time (tests), ISO format")
    args = parser.parse_args()

    now = dt.datetime.fromisoformat(args.now) if args.now else dt.datetime.now()
    scan_errors = list(args.scan_error)
    findings = load_findings(args.scan, scan_errors, args.running_kernel)

    # state: {key: finding} from the previous run, so a resolved finding can be
    # shown with the version it had and the version that fixes it.
    previous: dict = {}
    if args.state.is_file():
        try:
            loaded = json.loads(args.state.read_text())
            previous = loaded if isinstance(loaded, dict) else {k: None for k in loaded}
        except (OSError, json.JSONDecodeError):
            previous = {}
    new_keys = sorted(set(findings) - set(previous), key=lambda k: sort_key(findings[k]))
    fixed_keys = sorted(set(previous) - set(findings))

    upgraded, uu_errors = read_uu_log(args.uu_log, now - dt.timedelta(hours=args.since_hours))
    reboot_pkgs = []
    reboot_required = args.reboot_required_file.exists()
    pkgs_file = Path(str(args.reboot_required_file) + ".pkgs")
    if reboot_required and pkgs_file.is_file():
        reboot_pkgs = sorted(set(pkgs_file.read_text().split()))

    by_label: dict[str, dict[str, int]] = {}
    for item in findings.values():
        counts = by_label.setdefault(item["label"], {})
        counts[item["severity"]] = counts.get(item["severity"], 0) + 1

    # ---- full report -------------------------------------------------------
    lines = [f"Security report {now:%Y-%m-%d %H:%M}", ""]
    lines.append("== Host OS updates (unattended-upgrades, last "
                 f"{args.since_hours:g}h) ==")
    lines.append(("Installed: " + " ".join(upgraded)) if upgraded else "Nothing installed")
    for err in uu_errors:
        lines.append(f"ERROR: {err}")
    if reboot_required:
        lines.append("Reboot required" + (f" by: {' '.join(reboot_pkgs)}" if reboot_pkgs else ""))
    lines.append("")
    lines.append("== Fixable vulnerabilities still present (Trivy) ==")
    if not findings:
        lines.append("None")
    for label in sorted(by_label):
        summary = ", ".join(f"{sev} {n}" for sev, n in
                            sorted(by_label[label].items(), key=lambda p: SEVERITY_ORDER.get(p[0], 9)))
        lines.append(f"- {label}: {summary}")
    lines.append("")
    for item in sorted(findings.values(), key=sort_key):
        lines.append(fmt(item) + (" [NEW]" if f"{item['label']}|{item['pkg']}|{item['id']}" in new_keys else ""))
    if fixed_keys:
        lines.append("")
        lines.append(f"== Resolved since last scan: {len(fixed_keys)} ==")
        lines.extend(fmt_resolved(k, previous[k]) for k in fixed_keys)
    if scan_errors:
        lines.append("")
        lines.append("== Scan errors ==")
        lines.extend(f"- {label}: {msg}" for label, msg in scan_errors)
    args.report.write_text("\n".join(lines) + "\n")

    # ---- short message -----------------------------------------------------
    msg = []
    if new_keys:
        msg.append(f"🔴 New fixable vulnerabilities: {len(new_keys)}")
        msg.extend(fmt(findings[k]) for k in new_keys[:MAX_LISTED])
        if len(new_keys) > MAX_LISTED:
            msg.append(f"... and {len(new_keys) - MAX_LISTED} more")
    if fixed_keys:
        msg.append(f"✅ Resolved since last scan: {len(fixed_keys)}")
        msg.extend(fmt_resolved(k, previous[k]) for k in fixed_keys[:MAX_LISTED])
        if len(fixed_keys) > MAX_LISTED:
            msg.append(f"... and {len(fixed_keys) - MAX_LISTED} more")
    if upgraded:
        msg.append(f"📦 OS packages updated: {' '.join(upgraded[:30])}"
                   + (" ..." if len(upgraded) > 30 else ""))
    if uu_errors:
        msg.append("⚠️ unattended-upgrades errors:")
        msg.extend(uu_errors[:5])
    if reboot_required:
        msg.append("🔁 Reboot pending (auto-reboot window)"
                   + (f": {' '.join(reboot_pkgs)}" if reboot_pkgs else ""))
    if scan_errors:
        msg.append("⚠️ Scan errors:")
        msg.extend(f"{label}: {m}" for label, m in scan_errors[:5])
    if args.heartbeat:
        total = len(findings)
        msg.append(f"🗓 Weekly status: {total} fixable HIGH/CRITICAL open"
                   + ("" if total else " — all clean"))
        for label in sorted(by_label):
            msg.append(f"- {label}: {sum(by_label[label].values())}")

    args.message.write_text(("Security report\n" + "\n".join(msg) + "\n") if msg else "")
    args.state.write_text(json.dumps(findings, indent=1, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
