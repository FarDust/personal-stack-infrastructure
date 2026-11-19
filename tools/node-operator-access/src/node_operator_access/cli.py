"""Typer entry point: `render` prints the remote script; `apply` runs it with a safety session."""

import subprocess
import sys
from pathlib import Path
from typing import Annotated

import typer
from rich.console import Console

from node_operator_access.model import OperatorAccess
from node_operator_access.render import render_script

app = typer.Typer(no_args_is_help=True, help=__doc__)
err = Console(stderr=True)

_PUBKEY = Annotated[Path, typer.Option(exists=True, dir_okay=False, help="Dedicated overseer public key file.")]
_SOURCE = Annotated[str, typer.Option(help="Tailnet address of the only machine allowed to log in as overseer.")]


@app.command()
def render(public_key_file: _PUBKEY, source_ip: _SOURCE) -> None:
    """Print the remote script (review it before piping to `ssh <host> sudo bash -s`)."""
    access = OperatorAccess(public_key=public_key_file.read_text(encoding="utf-8"), source_ip=source_ip)
    sys.stdout.buffer.write(render_script(access).encode("utf-8"))  # LF only, also on Windows


@app.command()
def apply(
    host: Annotated[str, typer.Argument(help="ssh alias of an account with sudo")],
    public_key_file: _PUBKEY,
    source_ip: _SOURCE,
    private_key_file: Annotated[Path, typer.Option(exists=True, dir_okay=False)],
    execute: Annotated[bool, typer.Option("--execute", help="Run it; without this the plan is printed.")] = False,
) -> None:
    """Apply with a safety session held open, then prove the new login; the script rolls back itself."""
    access = OperatorAccess(public_key=public_key_file.read_text(encoding="utf-8"), source_ip=source_ip)
    script = render_script(access)
    if not execute:
        err.print(f"[yellow]Plan only[/]: would run the script below on {host} with a safety session.")
        sys.stdout.buffer.write(script.encode("utf-8"))
        return
    safety = subprocess.Popen(["ssh", host, "sleep 900"])  # stays open until the checks below finish
    try:
        subprocess.run(["ssh", host, "sudo", "bash", "-s"], input=script.encode("utf-8"), check=True)
        subprocess.run(
            [
                "ssh", "-i", str(private_key_file), "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes",
                f"overseer@{host}", "sudo -n true",
            ],
            check=True,
        )
    finally:
        safety.terminate()
    err.print("[green]overseer login and passwordless sudo verified[/]")
