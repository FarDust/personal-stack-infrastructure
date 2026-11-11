"""Thin rclone wrapper: rclone owns transfer, checksums and retries."""

import subprocess


class RcloneError(RuntimeError):
    pass


def run(binary: str, args: list[str]) -> str:
    result = subprocess.run([binary, *args], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise RcloneError(f"rclone {args[0]} failed ({result.returncode}): {result.stderr.strip()}")
    return result.stdout


def remote(bucket: str, prefix: str) -> str:
    return f":googlecloudstorage:{bucket}/{prefix}"
