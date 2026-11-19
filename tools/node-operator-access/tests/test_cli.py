"""CLI behaviour around failures: the CLI itself reverts, not only the remote trap."""

import subprocess
from pathlib import Path

import pytest
from typer.testing import CliRunner

from node_operator_access import cli

KEY = "ssh-ed25519 AAAAexamplekey overseer@example"
BACKUP = "/var/backups/node-operator-access-20261119T060000Z"


class _FakeSsh:
    def __init__(self, bootstrap_rc: int, check_rc: int, marker: bool = True, pair: str = KEY) -> None:
        self.bootstrap_rc, self.check_rc, self.marker, self.pair = bootstrap_rc, check_rc, marker, pair
        self.scripts: list[str] = []
        self.logins: list[list[str]] = []

    def run(self, argv, input=None, **_kw):  # noqa: A002 - mirrors subprocess.run
        if argv[0] == "ssh-keygen":
            return subprocess.CompletedProcess(argv, 0, stdout=self.pair.encode() + b"\n")
        if argv[-3:] == ["sudo", "bash", "-s"]:
            assert isinstance(input, bytes) and b"\r" not in input
            input = input.decode()
            if "operator access reverted" in input:
                self.scripts.append(input)
                return subprocess.CompletedProcess(argv, 0, stdout=b"operator access reverted\n")
            self.scripts.append(input)
            out = f"NODE_OPERATOR_ACCESS_BACKUP={BACKUP}\n".encode() if self.marker else b""
            return subprocess.CompletedProcess(argv, self.bootstrap_rc, stdout=out)
        self.logins.append(argv)
        return subprocess.CompletedProcess(argv, self.check_rc)


class _FakePopen:
    def __init__(self, *_a, **_kw) -> None:
        self.terminated = False

    def terminate(self) -> None:
        self.terminated = True


@pytest.fixture
def keys(tmp_path: Path) -> tuple[Path, Path]:
    pub, priv = tmp_path / "k.pub", tmp_path / "k"
    pub.write_text(KEY + "\n")
    priv.write_text("not-a-real-key\n")
    return pub, priv


def _invoke(monkeypatch, fake: _FakeSsh, keys) -> int:
    monkeypatch.setattr(cli.subprocess, "run", fake.run)
    monkeypatch.setattr(cli.subprocess, "Popen", _FakePopen)
    pub, priv = keys
    args = ["apply", "ubuntu@node", "--overseer-public-key-file", str(pub), "--source-ip", "100.64.0.1",
            "--overseer-private-key-file", str(priv), "--tailnet-host", "node.example.ts.net", "--execute"]
    return CliRunner().invoke(cli.app, args).exit_code


def test_failed_overseer_login_makes_the_cli_revert(monkeypatch, keys):
    fake = _FakeSsh(bootstrap_rc=0, check_rc=255)
    assert _invoke(monkeypatch, fake, keys) == 1
    assert len(fake.scripts) == 2 and f"BK=$ROOT{BACKUP}\n" in fake.scripts[1]
    assert fake.logins[0][-2] == "overseer@node.example.ts.net" and fake.logins[0][2] == str(keys[1])


def test_failed_bootstrap_still_runs_an_idempotent_revert(monkeypatch, keys):
    fake = _FakeSsh(bootstrap_rc=141, check_rc=0)
    assert _invoke(monkeypatch, fake, keys) == 1
    assert len(fake.scripts) == 2 and not fake.logins


def test_success_needs_the_backup_marker(monkeypatch, keys):
    assert _invoke(monkeypatch, _FakeSsh(0, 0, marker=False), keys) == 1
    assert _invoke(monkeypatch, _FakeSsh(0, 0), keys) == 0


def test_help_names_the_overseer_key_flags():
    out = CliRunner().invoke(cli.app, ["apply", "--help"], env={"COLUMNS": "240", "NO_COLOR": "1"}).output
    assert "--overseer-private-key-file" in out and "--overseer-public-key-file" in out
    assert "--private-key-file " not in out.replace("--overseer-private-key-file", "")


def test_mismatched_key_pair_stops_before_touching_the_node(monkeypatch, keys):
    fake = _FakeSsh(0, 0, pair="ssh-ed25519 AAAAotherkey other@example")
    assert _invoke(monkeypatch, fake, keys) == 2
    assert not fake.scripts and not fake.logins
