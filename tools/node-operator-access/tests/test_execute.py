"""Run the rendered scripts for real inside a temporary root, with fake system commands on PATH.

The fake `sshd -T` prints its match first and then far more than a pipe buffer, so a
`sshd -T | grep -q` check would die of SIGPIPE under pipefail (the 2026-11-19 exit 141).
"""

import os
import subprocess
from pathlib import Path

import pytest

from node_operator_access.model import OperatorAccess
from node_operator_access.render import parse_backup_dir, render_revert_script, render_script

from .conftest import BASH

pytestmark = pytest.mark.skipif(BASH is None, reason="needs a local bash (Git Bash on Windows)")

KEY = "ssh-ed25519 AAAAexamplekey overseer@example"
SRC = "100.64.0.1"

_FAKES = {
    "tailscale": 'printf "100.64.0.2\\nfd7a::2\\n"',
    "id": 'grep -qx "$1" "$FAKE_ROOT/users"',
    "useradd": 'u="${@: -1}"; echo "$u" >>"$FAKE_ROOT/users"; mkdir -p "$FAKE_ROOT/home/$u"',
    "userdel": 'u="${@: -1}"; grep -vx "$u" "$FAKE_ROOT/users" >"$FAKE_ROOT/users.new" || true; '
    'mv "$FAKE_ROOT/users.new" "$FAKE_ROOT/users"; rm -rf "$FAKE_ROOT/home/$u"',
    "passwd": "true",
    "chown": "true",
    "visudo": "true",
    "cp": 'if [ -n "${FAKE_CP_FAIL:-}" ] && [[ "$*" == *"$FAKE_CP_FAIL"* ]]; then exit 1; fi; exec /usr/bin/cp "$@"',
    "systemctl": 'echo "systemctl $*" >>"$FAKE_ROOT/calls"',
    "install": (
        'd=0; args=(); while [ $# -gt 0 ]; do case "$1" in -d) d=1;; -m|-o|-g) shift;; *) args+=("$1");; esac; shift; done; '
        'if [ $d = 1 ]; then mkdir -p "${args[@]}"; else cp "${args[0]}" "${args[1]}"; fi'
    ),
    "sshd": (
        '[ "$1" = -t ] && exit 0; spec="$3"; '
        'case "$spec" in '
        '"user=overseer,"*"addr=$FAKE_ALLOWED,"*) echo "allowusers overseer";; '
        '"user=overseer,"*) if [ "$FAKE_SSHD" = permissive ]; then echo "allowusers overseer"; '
        'else echo "allowusers nobody-matches-this"; fi;; '
        "esac; "
        'for i in $(seq 1 6000); do echo "setting$i value-padding-to-overflow-the-pipe-buffer"; done'
    ),
}


@pytest.fixture
def node(tmp_path: Path) -> dict[str, object]:
    root = tmp_path / "root"
    for d in ("etc/ssh/sshd_config.d", "etc/sudoers.d", "var/backups", "home"):
        (root / d).mkdir(parents=True)
    (root / "etc/ssh/sshd_config").write_text("Include /etc/ssh/sshd_config.d/*.conf\n")
    (root / "users").write_text("root\natelo\n")
    bindir = tmp_path / "bin"
    bindir.mkdir()
    for name, body in _FAKES.items():
        f = bindir / name
        f.write_bytes(f"#!/bin/bash\n{body}\n".encode())
        f.chmod(0o755)
    env = {**os.environ, "FAKE_ROOT": root.as_posix(), "FAKE_ALLOWED": SRC, "FAKE_SSHD": "strict"}
    env["PATH"] = f"{bindir.as_posix()}{os.pathsep}{env['PATH']}"
    return {"root": root, "env": env}


def _bash_path(p: Path) -> str:
    """Path as bash sees it (Git Bash on Windows maps C:/x to /c/x)."""
    out = subprocess.run([BASH, "-c", 'cd "$1" && pwd', "_", p.as_posix()], capture_output=True, text=True, check=True)
    return out.stdout.strip()


def _run(script: str, env: dict) -> subprocess.CompletedProcess[str]:
    # Bytes in, so Windows never turns the script's LF into CRLF on the way to bash.
    done = subprocess.run([BASH, "-s"], input=script.encode("utf-8"), capture_output=True, env=env)
    return subprocess.CompletedProcess(done.args, done.returncode, done.stdout.decode(), done.stderr.decode())


def _apply(node: dict) -> subprocess.CompletedProcess[str]:
    root = _bash_path(node["root"])
    return _run(render_script(OperatorAccess(public_key=KEY, source_ip=SRC), root=root), node["env"])


def test_apply_succeeds_with_large_sshd_output_and_reloads(node):
    done = _apply(node)
    assert done.returncode == 0, done.stderr
    root: Path = node["root"]
    assert (root / "home/overseer/.ssh/authorized_keys").read_text() == KEY + "\n"
    assert (root / "etc/sudoers.d/90-overseer-nopasswd").exists()
    assert "Match User overseer Address 100.64.0.1 LocalAddress 100.64.0.2" in (
        root / "etc/ssh/sshd_config.d/overseer-restrict.conf"
    ).read_text()
    assert "systemctl reload ssh" in (root / "calls").read_text()
    backup = parse_backup_dir(done.stdout)
    assert backup is not None and (root / backup.lstrip("/") / "created-user").exists()


def test_failed_check_rolls_back_and_removes_created_user(node):
    node["env"]["FAKE_SSHD"] = "permissive"
    done = _apply(node)
    assert done.returncode != 0
    assert "unexpected source" in done.stderr
    root: Path = node["root"]
    assert not (root / "home/overseer").exists()
    assert "overseer" not in (root / "users").read_text().split()
    assert not (root / "etc/sudoers.d/90-overseer-nopasswd").exists()
    assert not (root / "etc/ssh/sshd_config.d/overseer-restrict.conf").exists()


def test_revert_removes_everything_apply_added_and_is_idempotent(node):
    done = _apply(node)
    assert done.returncode == 0, done.stderr
    backup = parse_backup_dir(done.stdout)
    revert = render_revert_script(backup, root=_bash_path(node["root"]))
    for _ in range(2):
        again = _run(revert, node["env"])
        assert again.returncode == 0, again.stderr
    root: Path = node["root"]
    assert not (root / "home/overseer").exists()
    assert not (root / "etc/sudoers.d/90-overseer-nopasswd").exists()
    assert not (root / "etc/ssh/sshd_config.d/overseer-restrict.conf").exists()
    assert (root / "users").read_text().split() == ["root", "atelo"]


def test_revert_keeps_a_preexisting_overseer_and_restores_its_key(node):
    root: Path = node["root"]
    with (root / "users").open("a") as f:
        f.write("overseer\n")
    (root / "home/overseer/.ssh").mkdir(parents=True)
    (root / "home/overseer/.ssh/authorized_keys").write_text("ssh-ed25519 AAAAold old@example\n")
    done = _apply(node)
    assert done.returncode == 0, done.stderr
    revert = render_revert_script(parse_backup_dir(done.stdout), root=_bash_path(root))
    assert _run(revert, node["env"]).returncode == 0
    assert "overseer" in (root / "users").read_text().split()
    assert (root / "home/overseer/.ssh/authorized_keys").read_text() == "ssh-ed25519 AAAAold old@example\n"


def test_revert_rejects_a_foreign_backup_path():
    with pytest.raises(ValueError):
        render_revert_script("/etc")


def test_failed_backup_copy_leaves_live_files_and_cannot_be_reverted(node):
    root: Path = node["root"]
    sudoers = root / "etc/sudoers.d/90-overseer-nopasswd"
    drop = root / "etc/ssh/sshd_config.d/overseer-restrict.conf"
    sudoers.write_text("overseer ALL=(ALL) NOPASSWD:ALL\n")
    drop.write_text("Match User overseer\n    AllowUsers nobody-matches-this\n")
    node["env"]["FAKE_CP_FAIL"] = "90-overseer-nopasswd"
    done = _apply(node)
    assert done.returncode != 0
    assert parse_backup_dir(done.stdout) is None  # never announced, so the CLI never reverts it
    assert sudoers.exists() and drop.exists()  # live files untouched
    partial = next((root / "var/backups").iterdir())
    revert = render_revert_script("/var/backups/" + partial.name, root=_bash_path(root))
    refused = _run(revert, {**node["env"], "FAKE_CP_FAIL": ""})
    assert refused.returncode != 0 and "incomplete" in refused.stderr
    assert sudoers.exists() and drop.exists()
