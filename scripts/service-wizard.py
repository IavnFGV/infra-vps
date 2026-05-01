#!/usr/bin/env python3

import subprocess
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = ROOT_DIR / "scripts"
REGISTRY_DIR = ROOT_DIR / "registry" / "services"


def run(command: list[str]) -> str:
    print()
    print(f"> {' '.join(command)}")
    result = subprocess.run(command, cwd=ROOT_DIR, check=True, capture_output=True, text=True)
    return result.stdout.strip()


def ask(prompt: str, default: str | None = None) -> str:
    if default:
        value = input(f"{prompt} [{default}]: ").strip()
        return value or default

    value = input(f"{prompt}: ").strip()
    if not value:
        raise ValueError(f"Required value is empty: {prompt}")
    return value


def yes(value: str) -> bool:
    return value.strip().lower() in {"y", "yes"}


def proxy_mode(value: str) -> str:
    normalized = value.strip().lower()
    if normalized not in {"files", "proxy", "both"}:
        raise ValueError("Proxy mode must be one of 'files', 'proxy', or 'both'")
    return normalized


def script(name: str) -> str:
    path = SCRIPTS_DIR / name
    if not path.exists():
        raise FileNotFoundError(f"Script not found: {path}")
    return str(path)


def encrypt_value(plaintext: str) -> str:
    return run([script("encrypt-value.sh"), plaintext])


def main() -> None:
    print("Service registration wizard (GitOps mode)")
    print("This will create a service registry file locally.")
    print("After creation, commit and push to apply on the server.")

    service_name = ask("Service name, for example hello-test")
    domain = ask("Domain, for example hello-test-178-104-218-159.nip.io")
    upstream_host = ask("Upstream docker network alias, for example hello-test-app")
    upstream_port = ask("Upstream port", "80")

    enable_https_input = ask("Enable HTTPS? yes/no", "yes")
    enable_https = yes(enable_https_input)

    letsencrypt_email = ""
    if enable_https:
        letsencrypt_email_plain = ask("Let's Encrypt email (plaintext, will be encrypted)")
        letsencrypt_email = encrypt_value(letsencrypt_email_plain)

    static_enabled_input = ask("Enable static file serving? yes/no", "no")
    static_enabled = yes(static_enabled_input)

    proxy_mode_value = ""
    static_secret_encrypted = ""
    static_dir = ""
    if static_enabled:
        proxy_mode_value = proxy_mode(ask("Proxy mode: files, proxy, or both", "files"))
        static_public_prefix = ask("Static public prefix", "/static")
        static_secret_plain = ask("Static secret (plaintext, will be encrypted)")
        static_secret_encrypted = encrypt_value(static_secret_plain)
        if proxy_mode_value in {"files", "both"}:
            static_dir = ask("Static directory path", f"/srv/service-static/{service_name}")

    # Create registry directory if not exists
    REGISTRY_DIR.mkdir(parents=True, exist_ok=True)

    # Create env file
    env_file = REGISTRY_DIR / f"{service_name}.env"
    if env_file.exists():
        raise FileExistsError(f"Service registry file already exists: {env_file}")

    with open(env_file, "w") as f:
        f.write(f"SERVICE_NAME={service_name}\n")
        f.write(f"DOMAIN={domain}\n")
        f.write(f"UPSTREAM_HOST={upstream_host}\n")
        f.write(f"UPSTREAM_PORT={upstream_port}\n")
        f.write("\n")
        f.write(f"ENABLE_HTTPS={str(enable_https).lower()}\n")
        if enable_https:
            f.write(f"LETSENCRYPT_EMAIL={letsencrypt_email}\n")
        f.write("\n")
        f.write(f"STATIC_ENABLED={str(static_enabled).lower()}\n")
        if static_enabled:
            f.write(f"PROXY_MODE={proxy_mode_value}\n")
            f.write(f"STATIC_PUBLIC_PREFIX={static_public_prefix}\n")
            f.write(f"STATIC_SECRET={static_secret_encrypted}\n")
            if proxy_mode_value in {"files", "both"}:
                f.write(f"STATIC_DIR={static_dir}\n")

    print()
    print("Service registry file created:")
    print(f"  {env_file}")
    print()
    print("Next steps:")
    print("1. Ensure the service is running on the VPS in /opt/services/<service>")
    print("2. The service should be connected to the 'edge' docker network with alias as specified.")
    print("3. Run: git add registry/services/")
    print("4. Run: git commit -m 'Add service <service_name>'")
    print("5. Run: git push")
    print("6. GitHub Actions will apply the service on the server.")


if __name__ == "__main__":
    main()
