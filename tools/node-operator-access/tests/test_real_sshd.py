"""Evaluate the rendered sshd drop-in with a real OpenSSH `sshd -T -C`, when one is installed (CI on Ubuntu)."""

import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from node_operator_access.render import SSHD_DROPIN

SSHD = shutil.which("sshd") or ("/usr/sbin/sshd" if Path("/usr/sbin/sshd").exists() else None)
pytestmark = pytest.mark.skipif(sys.platform == "win32" or SSHD is None, reason="needs OpenSSH sshd on Linux")

SRC, TSIP = "100.64.0.1", "100.64.0.2"


@pytest.fixture
def config(tmp_path: Path) -> Path:
    hostkey = tmp_path / "hostkey"
    subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(hostkey)], check=True)
    cfg = tmp_path / "sshd_config"
    cfg.write_text(f"HostKey {hostkey}\nPidFile none\n" + SSHD_DROPIN.format(src=SRC, laddr=TSIP))
    if subprocess.run([SSHD, "-t", "-f", str(cfg)], capture_output=True).returncode != 0:
        pytest.skip("sshd cannot evaluate an alternate config here")
    return cfg


def _allowusers(cfg: Path, user: str, addr: str, laddr: str = TSIP) -> set[str]:
    out = subprocess.run(
        [SSHD, "-T", "-f", str(cfg), "-C", f"user={user},host=x,addr={addr},laddr={laddr},lport=22"],
        capture_output=True, text=True, check=True,
    ).stdout
    return {line.split(" ", 1)[1] for line in out.splitlines() if line.startswith("allowusers ")}


def test_permitted_source_on_the_tailnet_address_admits_overseer(config):
    assert "overseer" in _allowusers(config, "overseer", SRC)


@pytest.mark.parametrize(("addr", "laddr"), [("192.0.2.1", TSIP), (SRC, "10.0.0.5")])
def test_other_source_or_local_address_admits_nobody(config, addr, laddr):
    assert _allowusers(config, "overseer", addr, laddr) == {"nobody-matches-this"}


def test_other_users_are_unaffected(config):
    assert _allowusers(config, "atelo", "192.0.2.1") == set()
