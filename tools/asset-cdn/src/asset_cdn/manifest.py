"""Content-hashed object naming and the per-tenant manifest."""

import hashlib
import json
from datetime import UTC, datetime
from pathlib import Path

from pydantic import BaseModel, Field

IMMUTABLE_CACHE_CONTROL = "public, max-age=31536000, immutable"
MANIFEST_NAME = "manifest.json"
MANIFEST_CACHE_CONTROL = "no-cache"


class Entry(BaseModel):
    object: str = Field(description="Hashed object name under the tenant prefix.")
    bytes: int = Field(ge=0)
    sha256: str = Field(pattern=r"^[0-9a-f]{64}$")


class Manifest(BaseModel):
    version: int = 1
    tenant: str
    generated: str
    files: dict[str, Entry]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def hashed_name(digest: str, source: Path) -> str:
    return f"{digest[:16]}{source.suffix.lower()}"


def build_manifest(tenant: str, source_dir: Path) -> Manifest:
    """Hash every file under source_dir; logical paths are POSIX-relative and sorted."""
    if not source_dir.is_dir():
        raise FileNotFoundError(f"source directory not found: {source_dir}")
    files: dict[str, Entry] = {}
    for path in sorted(p for p in source_dir.rglob("*") if p.is_file()):
        digest = sha256_file(path)
        files[path.relative_to(source_dir).as_posix()] = Entry(
            object=hashed_name(digest, path), bytes=path.stat().st_size, sha256=digest
        )
    if not files:
        raise ValueError(f"no files under {source_dir}; refusing to publish an empty manifest")
    return Manifest(tenant=tenant, generated=datetime.now(UTC).isoformat(), files=files)


def stage(manifest: Manifest, source_dir: Path, staging: Path) -> None:
    """Copy each distinct object once under its hashed name; bytes stay identical."""
    staging.mkdir(parents=True, exist_ok=True)
    for logical, entry in manifest.files.items():
        target = staging / entry.object
        if not target.exists():
            target.write_bytes((source_dir / logical).read_bytes())


def dump(manifest: Manifest) -> str:
    return json.dumps(manifest.model_dump(), indent=2, sort_keys=True) + "\n"
