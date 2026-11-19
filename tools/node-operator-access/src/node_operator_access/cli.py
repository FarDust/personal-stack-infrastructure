"""Typer entry point: `render` prints the remote script, `apply` runs it with a safety session, `revert` undoes it."""

import subprocess
import sys
from pathlib import Path
from typing import Annotated

import typer
from rich.console import Console

from node_operator_access.model import OperatorAccess
from node_operator_access.render import parse_backup_dir, render_revert_script, render_script

app = typer.Typer(no_args_is_help=True, help=__doc__)
err = Console(stderr=True)

_PUBKEY = Annotated[
    Path,
    typer.Option(
        "--overseer-public-key-file",
        exists=True,
        dir_okay=False,
        help="Public half of the dedicated overseer key pair; installed as overseer's only authorized key.",
    ),
]
_SOURCE = Annotated[str, typer.Option(help="Tailnet address of the only machine allowed to log in as overseer.")]
_HOST = Annotated[
    str,
    typer.Argument(help="ssh destination of the existing sudo account (alias or user@host); its key comes from ssh config or --ssh-arg."),
]
_SKIP_ATELO = Annotated[
    bool,
    typer.Option(
        "--skip-atelo-check",
        help="Do not require a local atelo account (hosts where another identity, such as the OS Login owner, holds that role).",
    ),
]
_SSH_ARGS = Annotated[
    list[str] | None,
    typer.Option("--ssh-arg", help="Extra ssh argument for the sudo-account connections (repeatable), e.g. -i KEY."),
]


class _Remote:
    """ssh access through the existing sudo account."""

    def __init__(self, host: str, ssh_args: list[str]) -> None:
        self.host, self.ssh_args = host, ssh_args

    def argv(self, *command: str) -> list[str]:
        return ["ssh", *self.ssh_args, self.host, *command]

    def run_root_script(self, script: str) -> subprocess.CompletedProcess[str]:
        """Run a root script; stdout is captured (and echoed) so the backup marker can be read."""
        # Bytes in: text mode would turn LF into CRLF on Windows and bash would reject `set -o pipefail\r`.
        done = subprocess.run(self.argv("sudo", "bash", "-s"), input=script.encode("utf-8"), stdout=subprocess.PIPE)
        stdout = done.stdout.decode("utf-8", errors="replace")
        sys.stdout.write(stdout)
        return subprocess.CompletedProcess(done.args, done.returncode, stdout)

    def revert(self, backup_dir: str) -> bool:
        done = self.run_root_script(render_revert_script(backup_dir))
        if done.returncode == 0:
            err.print(f"[yellow]reverted[/] {self.host} from {backup_dir}")
            return True
        err.print(f"[red]revert failed[/] on {self.host} (exit {done.returncode}); backup kept in {backup_dir}")
        return False


def _check_pair(private_key: Path, public_key: str) -> None:
    """The proof key must be the private half of the key being installed."""
    derived = subprocess.run(
        ["ssh-keygen", "-y", "-P", "", "-f", str(private_key)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
    )
    body = public_key.split()[:2]
    if derived.returncode != 0 or derived.stdout.decode("ascii", errors="replace").split()[:2] != body:
        err.print("[red]--overseer-private-key-file is not the private half of --overseer-public-key-file[/]")
        raise typer.Exit(2)


@app.command()
def render(public_key_file: _PUBKEY, source_ip: _SOURCE, skip_atelo_check: _SKIP_ATELO = False) -> None:
    """Print the remote script (review it before piping to `ssh <host> sudo bash -s`)."""
    access = OperatorAccess(public_key=public_key_file.read_text(encoding="utf-8"), source_ip=source_ip)
    script = render_script(access, require_atelo=not skip_atelo_check)
    sys.stdout.buffer.write(script.encode("utf-8"))  # LF only, also on Windows


@app.command()
def apply(
    host: _HOST,
    public_key_file: _PUBKEY,
    source_ip: _SOURCE,
    overseer_private_key_file: Annotated[
        Path,
        typer.Option(
            exists=True,
            dir_okay=False,
            help="Private half of the overseer key pair (checked against --overseer-public-key-file); used only "
            "for the post-apply `overseer@<tailnet-host> sudo -n true` proof, never for the sudo account.",
        ),
    ],
    tailnet_host: Annotated[
        str,
        typer.Option(help="Node's tailnet name or 100.x address for the proof; sshd only admits overseer there."),
    ],
    ssh_arg: _SSH_ARGS = None,
    skip_atelo_check: _SKIP_ATELO = False,
    execute: Annotated[bool, typer.Option("--execute", help="Run it; without this the plan is printed.")] = False,
) -> None:
    """Apply with a safety session held open, prove the new login, and revert on any failure."""
    access = OperatorAccess(public_key=public_key_file.read_text(encoding="utf-8"), source_ip=source_ip)
    script = render_script(access, require_atelo=not skip_atelo_check)
    if not execute:
        err.print(f"[yellow]Plan only[/]: would run the script below on {host} with a safety session.")
        sys.stdout.buffer.write(script.encode("utf-8"))
        return
    _check_pair(overseer_private_key_file, access.public_key)
    remote = _Remote(host, list(ssh_arg or []))
    safety = subprocess.Popen(remote.argv("sleep 900"))  # stays open until the checks below finish
    try:
        done = remote.run_root_script(script)
        backup_dir = parse_backup_dir(done.stdout)
        if done.returncode != 0:
            err.print(f"[red]bootstrap failed[/] on {host} (exit {done.returncode}); the remote trap reverted it")
            if backup_dir is not None:
                remote.revert(backup_dir)  # idempotent second pass: the trap may have been cut off
            raise typer.Exit(1)
        if backup_dir is None:
            err.print("[red]bootstrap reported success without a backup marker[/]; not verified")
            raise typer.Exit(1)
        check = subprocess.run(
            [
                "ssh", "-i", str(overseer_private_key_file), "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes",
                f"overseer@{tailnet_host}", "sudo -n true",
            ],
        )
        if check.returncode != 0:
            err.print(f"[red]overseer login or sudo failed[/] (exit {check.returncode}); reverting")
            remote.revert(backup_dir)
            raise typer.Exit(1)
    finally:
        safety.terminate()
    err.print(f"[green]overseer login and passwordless sudo verified[/]; backup in {backup_dir}")


@app.command()
def revert(
    host: _HOST,
    backup_dir: Annotated[str, typer.Option(help="Directory printed as NODE_OPERATOR_ACCESS_BACKUP=... by apply.")],
    ssh_arg: _SSH_ARGS = None,
) -> None:
    """Restore the files from one backup and remove the overseer account when apply created it."""
    if not _Remote(host, list(ssh_arg or [])).revert(backup_dir):
        raise typer.Exit(1)
