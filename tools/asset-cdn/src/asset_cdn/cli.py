"""Typer entry point: publish and verify tenant assets."""

import tempfile
from pathlib import Path
from typing import Annotated

import httpx
import typer
from rich.console import Console
from rich.table import Table

from asset_cdn import manifest as mf
from asset_cdn import rclone
from asset_cdn.settings import Settings

app = typer.Typer(no_args_is_help=True, help="Private tailnet asset CDN operations.")
console = Console(stderr=True)

_GCS = ["--gcs-bucket-policy-only"]


@app.command()
def publish(
    tenant: Annotated[str, typer.Argument(help="Tenant prefix, for example a project slug.")],
    source: Annotated[Path, typer.Argument(help="Directory holding the assets to publish.")],
    prune: Annotated[bool, typer.Option(help="Delete tenant objects the new manifest no longer lists.")] = False,
    dry_run: Annotated[bool, typer.Option(help="Hash and report without uploading.")] = False,
) -> None:
    """Upload content-hashed objects, then the manifest, so readers never see a dangling manifest."""
    settings = Settings()
    manifest = mf.build_manifest(tenant, source)
    table = Table("logical path", "object", "bytes")
    for logical, entry in manifest.files.items():
        table.add_row(logical, entry.object, str(entry.bytes))
    console.print(table)
    if dry_run:
        console.print(f"dry run: {len(manifest.files)} files, nothing uploaded")
        return
    destination = rclone.remote(settings.bucket, tenant)
    with tempfile.TemporaryDirectory() as tmp:
        staging = Path(tmp) / "objects"
        mf.stage(manifest, source, staging)
        rclone.run(
            settings.rclone,
            [
                "copy", str(staging), destination, *_GCS, "--checksum", "--transfers", "4", "--retries", "3",
                "--header-upload", f"Cache-Control: {mf.IMMUTABLE_CACHE_CONTROL}",
            ],
        )
        manifest_path = Path(tmp) / mf.MANIFEST_NAME
        manifest_path.write_text(mf.dump(manifest), encoding="utf-8", newline="\n")
        rclone.run(
            settings.rclone,
            [
                "copyto", str(manifest_path), f"{destination}/{mf.MANIFEST_NAME}", *_GCS,
                "--header-upload", f"Cache-Control: {mf.MANIFEST_CACHE_CONTROL}",
            ],
        )
    if prune:
        keep = {entry.object for entry in manifest.files.values()} | {mf.MANIFEST_NAME}
        listed = rclone.run(settings.rclone, ["lsf", destination, *_GCS, "--files-only"]).splitlines()
        for name in (n for n in listed if n and n not in keep):
            rclone.run(settings.rclone, ["deletefile", f"{destination}/{name}", *_GCS])
            console.print(f"pruned {tenant}/{name}")
    console.print(f"published {len(manifest.files)} files for {tenant}")


@app.command()
def verify(
    tenant: Annotated[str, typer.Argument(help="Tenant prefix to check through the connector.")],
) -> None:
    """Fetch the manifest through the connector and confirm each object exists with its size."""
    settings = Settings()
    base = f"{settings.base_url}/{tenant}"
    with httpx.Client(timeout=30.0) as client:
        response = client.get(f"{base}/{mf.MANIFEST_NAME}")
        response.raise_for_status()
        manifest = mf.Manifest.model_validate_json(response.text)
        failures: list[str] = []
        for logical, entry in manifest.files.items():
            head = client.head(f"{base}/{entry.object}")
            length = head.headers.get("content-length")
            if head.status_code != 200 or length is None or int(length) != entry.bytes:
                failures.append(f"{logical}: status {head.status_code}, length {length}, expected {entry.bytes}")
    if failures:
        for failure in failures:
            console.print(f"[red]FAIL[/red] {failure}")
        raise typer.Exit(code=1)
    console.print(f"verified {len(manifest.files)} objects for {tenant}")
