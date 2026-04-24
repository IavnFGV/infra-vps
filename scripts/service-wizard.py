#!/usr/bin/env python3

import subprocess
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = ROOT_DIR / "scripts"


def run(command: list[str]) -> None:
    print()
    print(f"> {' '.join(command)}")
    subprocess.run(command, cwd=ROOT_DIR, check=True)


def ask(prompt: str, default: str | None = None) -> str:
    if default:
        value = input(f"{prompt} [{default}]: ").strip()
        return value or default

    value = input(f"{prompt}: ").strip()
    if not value:
        raise ValueError(f"Required value is empty: {prompt}")
    return value


def yes(value: str) -> bool:
    return value.strip().lower() in {"y", "yes", "д", "да"}


def script(name: str) -> str:
    path = SCRIPTS_DIR / name
    if not path.exists():
        raise FileNotFoundError(f"Script not found: {path}")
    return str(path)


def main() -> None:
    print("Service onboarding wizard")

    site_name = ask("Site name, for example hello")
    domain = ask("Domain, for example hello-178-104-218-159.nip.io")
    upstream_host = ask("Upstream docker network alias, for example hello-app")
    upstream_port = ask("Upstream port", "80")
    enable_https = ask("Issue certificate and enable HTTPS? yes/no", "yes")

    run([
        script("add-site.sh"),
        site_name,
        domain,
        upstream_host,
        upstream_port,
    ])

    run([script("check-nginx.sh")])
    run([script("reload-nginx.sh")])

    if yes(enable_https):
        email = ask("Let's Encrypt email")

        run([
            script("issue-cert.sh"),
            domain,
            email,
        ])

        run([
            script("enable-https.sh"),
            site_name,
            domain,
            upstream_host,
            upstream_port,
        ])

        run([script("check-nginx.sh")])
        run([script("reload-nginx.sh")])

    print()
    print("Done.")
    print(f"HTTP:  http://{domain}")

    if yes(enable_https):
        print(f"HTTPS: https://{domain}")


if __name__ == "__main__":
    main()