import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class DeployInfraTests(unittest.TestCase):
    def run_deploy(self, nginx_test_status=0):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            (root / "bin").mkdir()
            stack_dir = root / "hello-test"
            stack_dir.mkdir()
            for name in (
                "006-deploy-infra.sh",
                "init-edge-network.sh",
                "check-nginx.sh",
            ):
                shutil.copy2(ROOT / "scripts" / name, root / "scripts" / name)
            docker = root / "bin" / "docker"
            docker.write_text(
                '#!/usr/bin/env bash\n'
                'printf "%s @%s\\n" "$*" "$PWD" >> "$DOCKER_CALLS"\n'
                'if [[ "$1" == ps ]]; then printf "c1\\nc2\\nc3\\n"; exit 0; fi\n'
                'if [[ "$1" == inspect ]]; then\n'
                '  printf "infra-vps-nginx:local\\tinfra-vps\\t/infra\\n"\n'
                '  printf "infra-vps-nginx:local\\thello-test\\t%s\\n" "$STACK_DIR"\n'
                '  printf "englishbot-app\\tenglishbot\\t/elsewhere\\n"\n'
                '  exit 0\n'
                'fi\n'
                'if [[ "$*" == "compose run "* ]]; then\n'
                '  cat >/dev/null\n'
                '  exit "$NGINX_TEST_STATUS"\n'
                'fi\n'
            )
            docker.chmod(0o755)
            env = {
                **os.environ,
                "PATH": f"{root / 'bin'}:{os.environ['PATH']}",
                "DOCKER_CALLS": str(root / "docker-calls"),
                "STACK_DIR": str(stack_dir),
                "NGINX_TEST_STATUS": str(nginx_test_status),
                "CERTBOT_UID": "1000",
                "CERTBOT_GID": "1000",
            }
            result = subprocess.run(
                ["bash", "-se"],
                input='./scripts/006-deploy-infra.sh\nprintf "CI_DONE\\n"\n',
                text=True,
                capture_output=True,
                cwd=root,
                env=env,
            )
            return result, (root / "docker-calls").read_text()

    def test_deploy_preserves_remaining_ci_commands(self):
        result, calls = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CI_DONE", result.stdout)
        self.assertIn("compose pull certbot", calls)
        self.assertRegex(calls, r"compose build --pull --build-arg SECURITY_REFRESH=\d{8}T\d{6} nginx")
        self.assertLess(calls.index("compose build"), calls.index("compose run"))
        self.assertIn("--interactive=false", calls)
        self.assertLess(calls.index("compose run"), calls.index("compose up"))

    def test_recreates_other_stacks_using_the_nginx_image(self):
        result, calls = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        recreated = [line for line in calls.splitlines() if line.startswith("compose up -d --wait")]
        self.assertEqual(len(recreated), 1, calls)
        self.assertTrue(recreated[0].endswith("/hello-test"), recreated)
        self.assertLess(calls.index("compose up -d nginx"), calls.index("compose up -d --wait"))

    def test_invalid_nginx_config_prevents_recreation(self):
        result, calls = self.run_deploy(nginx_test_status=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("compose up", calls)
        self.assertNotIn("CI_DONE", result.stdout)


if __name__ == "__main__":
    unittest.main()
