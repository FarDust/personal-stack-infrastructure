"""Typed, validated inputs for the operator-account bootstrap."""

import re

from pydantic import BaseModel, field_validator

_TAILNET_IP = re.compile(r"^100(\.[0-9]{1,3}){3}$")
# Strict: base64 body and a plain comment, so the key can never carry shell syntax (it is
# also shlex-quoted when rendered).
_ED25519 = re.compile(r"^ssh-ed25519 [A-Za-z0-9+/]+={0,2}( [A-Za-z0-9@._+-]+)?$")


class OperatorAccess(BaseModel, frozen=True):
    """The `overseer` account: key only, passwordless sudo, one allowed source address."""

    public_key: str
    source_ip: str

    @field_validator("public_key")
    @classmethod
    def _key(cls, v: str) -> str:
        if not _ED25519.fullmatch(v.strip()):
            raise ValueError("public_key must be a single-line ssh-ed25519 public key")
        return v.strip()

    @field_validator("source_ip")
    @classmethod
    def _ip(cls, v: str) -> str:
        if not _TAILNET_IP.fullmatch(v):
            raise ValueError("source_ip must be a tailnet (100.x.y.z) IPv4 address")
        return v
