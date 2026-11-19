"""Shared test helpers: a bash that runs on this machine, never the WSL launcher."""

import shutil
import sys
from pathlib import Path


def local_bash() -> str | None:
    """Git Bash on Windows (System32\bash.exe would run the script inside WSL), plain bash elsewhere."""
    if sys.platform != "win32":
        return shutil.which("bash")
    git = shutil.which("git")
    if git is None:
        return None
    for parent in Path(git).resolve().parents:
        # usr/bin/bash.exe keeps PATH as given; the bin/bash.exe wrapper puts /usr/bin first.
        for candidate in (parent / "usr" / "bin" / "bash.exe", parent / "bin" / "bash.exe"):
            if candidate.is_file():
                return str(candidate)
    return None


BASH = local_bash()
