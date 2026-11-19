import re
import shutil
import subprocess

import pytest
from pydantic import ValidationError

from node_operator_access.model import OperatorAccess
from node_operator_access.render import render_script

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
    assert "SRC='100.64.0.1'" in s


def test_validation_and_rollback_present():
    s = _script()
    assert "visudo -cf" in s and "sshd -t" in s and "trap" in s and "rollback()" in s


@pytest.mark.skipif(shutil.which("bash") is None, reason="needs bash")
def test_script_is_valid_bash_and_fully_rendered():
    s = _script()
    assert subprocess.run(["bash", "-n"], input=s.encode("utf-8")).returncode == 0
    assert not re.search(r"@(SRC|KEY)@", s)
