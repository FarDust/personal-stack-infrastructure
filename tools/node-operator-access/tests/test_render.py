import re
import subprocess

import pytest
from pydantic import ValidationError

from node_operator_access.model import OperatorAccess
from node_operator_access.render import render_script

from .conftest import BASH

KEY = "ssh-ed25519 AAAAexamplekey overseer@example"


def _script() -> str:
    return render_script(OperatorAccess(public_key=KEY, source_ip="100.64.0.1"))


def test_rejects_non_ed25519_and_public_source():
    with pytest.raises(ValidationError):
        OperatorAccess(public_key="ssh-rsa AAAA", source_ip="100.64.0.1")
    with pytest.raises(ValidationError):
        OperatorAccess(public_key=KEY, source_ip="203.0.113.5")


def test_same_keyword_in_both_match_blocks_and_publickey():
    s = _script()
    assert "DenyUsers" not in s
    assert s.count("    AllowUsers") == 2 and s.count("AuthenticationMethods publickey") == 2
    assert "Match User overseer Address $SRC LocalAddress $TSIP" in s
    assert "SRC=100.64.0.1" in s


def test_validation_and_rollback_present():
    s = _script()
    assert "visudo -cf" in s and "sshd -t" in s and "trap" in s and "rollback()" in s


@pytest.mark.skipif(BASH is None, reason="needs a local bash (Git Bash on Windows)")
def test_script_is_valid_bash_and_fully_rendered():
    s = _script()
    assert subprocess.run([BASH, "-n"], input=s.encode("utf-8")).returncode == 0
    assert not re.search(r"@(SRC|KEY)@", s)


def test_no_sshd_or_tailscale_output_is_piped_under_pipefail():
    s = _script()
    assert not re.search(r"sshd -T[^\n]*\|", s)
    assert not re.search(r"tailscale ip[^\n]*\|", s)
    assert "<<<\"$out\"" in s


@pytest.mark.parametrize(
    "key",
    [
        "ssh-ed25519 AAAA x'$(id)'",
        "ssh-ed25519 AAAA x$(id)",
        "ssh-ed25519 AAAA `id`",
        "ssh-ed25519 AAAA a;id",
        "ssh-ed25519 AAAA\nid",
    ],
)
def test_key_with_shell_syntax_is_rejected(key):
    with pytest.raises(ValidationError):
        OperatorAccess(public_key=key, source_ip="100.64.0.1")


def test_key_is_shell_quoted_when_rendered():
    s = _script()
    assert "KEY='ssh-ed25519 AAAAexamplekey overseer@example'" in s


def test_restriction_is_enforced_before_any_credential_exists():
    s = _script()
    assert s.index("systemctl reload ssh\n\n# 2.") < s.index("useradd") < s.index('"$AUTHKEYS"\nchown')
    assert s.index("sshd -t\n") < s.index("useradd")


def test_atelo_check_can_be_skipped_but_atelo_isolation_is_still_simulated():
    access = OperatorAccess(public_key=KEY, source_ip="100.64.0.1")
    assert "atelo account missing" in render_script(access)
    skipped = render_script(access, require_atelo=False)
    assert "atelo account missing" not in skipped and "effective atelo 192.0.2.1" in skipped
