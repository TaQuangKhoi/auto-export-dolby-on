import os
import shutil
import subprocess
import shlex
import sys
from pathlib import Path

from domain.exceptions import AdbNotFoundError, AdbCommandError


class AdbClient:
    def __init__(self, config: dict):
        self._config = config
        self._adb_path: str | None = None

    @property
    def adb_path(self) -> str:
        if self._adb_path is None:
            self._adb_path = self._find_adb()
            if not self._adb_path:
                raise AdbNotFoundError(self._not_found_message())
        return self._adb_path

    def _find_adb(self) -> str | None:
        path = shutil.which("adb")
        if path:
            return path

        explicit = os.environ.get("ADB_PATH")
        if explicit and os.path.exists(explicit):
            return explicit

        android_home = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
        if android_home:
            exe = "adb.exe" if os.name == "nt" else "adb"
            candidate = Path(android_home) / "platform-tools" / exe
            if candidate.exists():
                return str(candidate)

        return None

    def _not_found_message(self) -> str:
        return (
            "'adb' executable not found.\n"
            "Install Android Platform-tools and add 'adb' to your PATH,\n"
            "or set ADB_PATH, ANDROID_HOME, or ANDROID_SDK_ROOT."
        )

    def _run(self, args: list[str]) -> None:
        try:
            subprocess.run(args, check=True)
        except FileNotFoundError:
            raise AdbCommandError(f"Executable not found: {args[0]}")
        except subprocess.CalledProcessError as e:
            raise AdbCommandError(f"ADB command failed (exit {e.returncode}): {' '.join(e.cmd)}")

    def find_adb(self) -> str | None:
        return self._find_adb()

    def tap_at(self, x: int, y: int) -> None:
        self._run([self.adb_path, "shell", "input", "tap", str(x), str(y)])

    def dump_ui(self) -> str:
        result = subprocess.run(
            [self.adb_path, "exec-out", "uiautomator", "dump", "/dev/tty"],
            capture_output=True, text=True
        )
        output = result.stdout
        import re
        match = re.search(r'(<\?xml.*?<hierarchy.*?</hierarchy>|'
                          r'<hierarchy.*?</hierarchy>)', output, re.DOTALL)
        if match:
            return match.group(1)
        raise AdbNotFoundError(f"Could not parse UI dump: {output[:200]}")