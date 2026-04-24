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
    main()#!/usr/bin/env python3

import shutil
import subprocess
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = ROOT_DIR / "scripts"
NGINX_SITES_DIR = ROOT_DIR / "nginx" / "sites"
SERVICES_DIR = Path("/opt/services")
STATIC_DIR = Path("/srv/service-static")


def run(command: list[str], cwd: Path | None = None) -> None:
    workdir = cwd or ROOT_DIR
    print()
    print(f"> {' '.join(command)}")
    subprocess.run(command, cwd=workdir, check=True)


def ask(prompt: str, default: str | None = None) -> str:
    if default is not None:
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


def list_sites() -> list[str]:
    if not NGINX_SITES_DIR.exists():
        return []

    return sorted(
        path.stem
        for path in NGINX_SITES_DIR.glob("*.conf")
        if path.is_file()
    )


def remove_nginx_site(service_name: str) -> None:
    site_file = NGINX_SITES_DIR / f"{service_name}.conf"

    if not site_file.exists():
        print(f"Nginx site config not found: {site_file}")
        return

    site_file.unlink()
    print(f"Removed nginx site config: {site_file}")


def stop_service(service_name: str) -> None:
    service_dir = SERVICES_DIR / service_name
    compose_file = service_dir / "docker-compose.yml"

    if not compose_file.exists():
        print(f"Service compose file not found: {compose_file}")
        return

    run(["docker", "compose", "down"], cwd=service_dir)


def delete_service_dir(service_name: str) -> None:
    service_dir = SERVICES_DIR / service_name

    if not service_dir.exists():
        print(f"Service directory not found: {service_dir}")
        return

    shutil.rmtree(service_dir)
    print(f"Removed service directory: {service_dir}")


def delete_static_dir(service_name: str) -> None:
    static_dir = STATIC_DIR / service_name

    if not static_dir.exists():
        print(f"Static directory not found: {static_dir}")
        return

    shutil.rmtree(static_dir)
    print(f"Removed static directory: {static_dir}")


def main() -> None:
    print("Service removal wizard")
    print()

    sites = list_sites()
    if sites:
        print("Existing nginx sites:")
        for site in sites:
            print(f"  - {site}")
        print()
    else:
        print("No nginx sites found.")
        print()

    service_name = ask("Service/site name to remove, for example hello2")

    print()
    print("This wizard can remove:")
    print(f"  nginx site:       {NGINX_SITES_DIR / f'{service_name}.conf'}")
    print(f"  service dir:      {SERVICES_DIR / service_name}")
    print(f"  static dir:       {STATIC_DIR / service_name}")
    print()
    print("Certificates are NOT deleted by default.")
    print("That is intentional. Deleting certificates automatically is how people create annoying little outages.")

    confirm = ask("Continue? yes/no", "no")
    if not yes(confirm):
        print("Cancelled.")
        return

    stop = ask("Stop docker service if /opt/services/<name>/docker-compose.yml exists? yes/no", "yes")
    delete_service = ask("Delete service directory from /opt/services? yes/no", "no")
    delete_static = ask("Delete static directory from /srv/service-static? yes/no", "no")

    if yes(stop):
        stop_service(service_name)

    remove_nginx_site(service_name)

    run([script("check-nginx.sh")])
    run([script("reload-nginx.sh")])

    if yes(delete_service):
        delete_service_dir(service_name)

    if yes(delete_static):
        delete_static_dir(service_name)

    print()
    print("Done.")
    print(f"Removed nginx routing for: {service_name}")


if __name__ == "__main__":
    main()