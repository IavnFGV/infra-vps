#!/usr/bin/env python3

from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parent.parent
REGISTRY_DIR = ROOT_DIR / "registry" / "services"


def ask(prompt: str, default: str | None = None) -> str:
    if default is not None:
        value = input(f"{prompt} [{default}]: ").strip()
        return value or default

    value = input(f"{prompt}: ").strip()
    if not value:
        raise ValueError(f"Required value is empty: {prompt}")
    return value


def yes(value: str) -> bool:
    return value.strip().lower() in {"y", "yes"}


def list_services() -> list[str]:
    if not REGISTRY_DIR.exists():
        return []

    return sorted(
        path.stem
        for path in REGISTRY_DIR.glob("*.env")
        if path.is_file()
    )


def main() -> None:
    print("Service removal wizard (GitOps mode)")
    print("This will remove a service registry file locally.")
    print("After removal, commit and push to remove from the server.")

    services = list_services()
    if services:
        print("Existing services:")
        for service in services:
            print(f"  - {service}")
        print()
    else:
        print("No services found.")
        return

    service_name = ask("Service name to remove, for example hello-test")

    env_file = REGISTRY_DIR / f"{service_name}.env"
    if not env_file.exists():
        print(f"Service registry file not found: {env_file}")
        return

    confirm = ask("Remove this service? yes/no", "no")
    if not yes(confirm):
        print("Cancelled.")
        return

    env_file.unlink()
    print(f"Removed service registry file: {env_file}")

    print()
    print("Next steps:")
    print("1. Run: git add registry/services/")
    print("2. Run: git commit -m 'Remove service <service_name>'")
    print("3. Run: git push")
    print("4. GitHub Actions will remove the service on the server.")


if __name__ == "__main__":
    main()