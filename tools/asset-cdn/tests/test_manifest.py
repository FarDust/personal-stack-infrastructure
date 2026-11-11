from pathlib import Path

import pytest

from asset_cdn import manifest as mf


def test_manifest_hashes_and_names_objects(tmp_path: Path) -> None:
    (tmp_path / "a").mkdir()
    (tmp_path / "a" / "one.JPG").write_bytes(b"alpha")
    (tmp_path / "two.png").write_bytes(b"beta")
    manifest = mf.build_manifest("example-app", tmp_path)
    assert set(manifest.files) == {"a/one.JPG", "two.png"}
    entry = manifest.files["a/one.JPG"]
    assert entry.object == f"{entry.sha256[:16]}.jpg" and entry.bytes == 5


def test_stage_keeps_bytes_identical_and_dedupes(tmp_path: Path) -> None:
    src, staging = tmp_path / "src", tmp_path / "out"
    src.mkdir()
    (src / "x.bin").write_bytes(b"same")
    (src / "y.bin").write_bytes(b"same")
    manifest = mf.build_manifest("example-app", src)
    mf.stage(manifest, src, staging)
    assert len(list(staging.iterdir())) == 1
    assert next(staging.iterdir()).read_bytes() == b"same"


def test_empty_source_is_an_explicit_failure(tmp_path: Path) -> None:
    with pytest.raises(ValueError):
        mf.build_manifest("example-app", tmp_path)
    with pytest.raises(FileNotFoundError):
        mf.build_manifest("example-app", tmp_path / "missing")
