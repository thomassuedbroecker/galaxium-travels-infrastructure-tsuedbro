from __future__ import annotations

import os
import shlex
import subprocess
from dataclasses import dataclass

from .models import Variant


class ComposeCommandError(RuntimeError):
    """Raised when docker compose fails for a test stack."""


def _as_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def docker_available() -> tuple[bool, str]:
    try:
        process = subprocess.run(
            ["docker", "info"],
            check=False,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        return False, "docker is not installed or not on PATH"

    if process.returncode != 0:
        message = (process.stderr or process.stdout or "docker info failed").strip()
        return False, message
    return True, "ok"


@dataclass
class ComposeStack:
    variant: Variant

    def _compose_command(self, *args: str) -> list[str]:
        command = ["docker", "compose"]
        for compose_file in self.variant.compose_files:
            command.extend(["-f", str(compose_file)])
        command.extend(args)
        return command

    def _run(self, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env.update(self.variant.compose_env)
        command = self._compose_command(*args)
        process = subprocess.run(
            command,
            cwd=self.variant.repo_root,
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )
        if check and process.returncode != 0:
            raise ComposeCommandError(
                "command failed: {command}\nstdout:\n{stdout}\nstderr:\n{stderr}".format(
                    command=shlex.join(command),
                    stdout=process.stdout.strip(),
                    stderr=process.stderr.strip(),
                )
            )
        return process

    def up(self) -> None:
        self.down()
        args = ["up", "-d"]
        if not _as_bool(os.getenv("WEBUI_TEST_SKIP_BUILD"), default=False):
            args.append("--build")
        args.extend(self.variant.compose_services)
        self._run(*args)

    def down(self) -> None:
        self._run("down", "--remove-orphans", check=False)

    def logs(self) -> str:
        process = self._run("logs", "--no-color", check=False)
        output = (process.stdout or "").strip()
        error_output = (process.stderr or "").strip()
        return "\n".join(part for part in [output, error_output] if part)
