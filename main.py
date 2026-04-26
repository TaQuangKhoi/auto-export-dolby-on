import sys
import time
from typing import Optional

import typer
from rich.console import Console
from rich.table import Table
from rich import box
from rich.panel import Panel
from rich.progress import Progress, TextColumn, BarColumn

from domain.exceptions import AdbNotFoundError
from domain.interfaces import IAdbClient, IDolbyApp, IUiAutomator, ICoordinates
from infrastructure.adb import AdbClient
from infrastructure.ui import UiAutomator, DolbyAppHelper, Coordinates
from application.use_cases import (
    ExportTrackUseCase,
    DeleteTrackUseCase,
    ProcessAllTracksUseCase,
    ListTracksUseCase,
    GetDeviceStatusUseCase,
)


CONFIG = {
    "EnableDump": False,
    "EnableReport": False,
    "DumpsFolder": "dumps",
    "WaitTimes": {
        "AppStabilize": 2,
        "ScreenLoad": 2,
        "PopupAppear": 2,
        "SaveDialog": 3,
        "ReturnToDetail": 2,
        "DeleteConfirm": 1,
        "ExportMaxWait": 300,
        "ExportCheckInterval": 2,
    },
    "DolbyApp": {
        "Package": "com.dolby.dolby234",
        "ResourceIds": {
            "RecyclerView": "com.dolby.dolby234:id/library_items_recycler_view",
            "TrackItem": "com.dolby.dolby234:id/swipe_layout",
            "Title": "com.dolby.dolby234:id/title_text_view",
            "Date": "com.dolby.dolby234:id/date_text_view",
            "Time": "com.dolby.dolby234:id/time_text_view",
            "ShareButton": "com.dolby.dolby234:id/track_details_share",
            "MoreButton": "com.dolby.dolby234:id/track_details_more",
            "ExportLossless": "com.dolby.dolby234:id/share_option_lossless_audio_item",
            "DeleteOption": "android:id/text1",
            "ConfirmDeleteButton": "android:id/button1",
        },
    },
    "AndroidSystem": {
        "DocumentsUiPackage": "com.android.documentsui",
        "SaveButtonText": "Save",
    },
}

app = typer.Typer(help="Dolby On automation CLI — export & delete tracks via ADB")


class AppContext:
    def __init__(self):
        self._adb_client: Optional[AdbClient] = None
        self._ui_automator: Optional[UiAutomator] = None
        self._dolby_app: Optional[DolbyAppHelper] = None
        self._coords: Optional[Coordinates] = None
        self._initialized = False

    def ensure(self) -> None:
        if self._initialized:
            return
        self._adb_client = AdbClient(CONFIG)
        if not self._adb_client.find_adb():
            raise AdbNotFoundError(self._adb_client._not_found_message())
        self._ui_automator = UiAutomator(self._adb_client, CONFIG)
        self._dolby_app = DolbyAppHelper(CONFIG)
        self._coords = Coordinates()
        self._initialized = True

    @property
    def adb(self) -> IAdbClient:
        self.ensure()
        return self._adb_client

    @property
    def ui(self) -> IUiAutomator:
        self.ensure()
        return self._ui_automator

    @property
    def dolby(self) -> IDolbyApp:
        self.ensure()
        return self._dolby_app

    @property
    def coords(self) -> ICoordinates:
        self.ensure()
        return self._coords


ctx = AppContext()


def _require_dolby_foreground() -> None:
    status = GetDeviceStatusUseCase(ctx.adb, CONFIG).execute()
    if not status["is_dolby_foreground"]:
        typer.secho(
            f"Dolby On ({status['dolby_app_package']}) is not in the foreground.\n"
            f"Current foreground app: {status['foreground_package'] or 'unknown'}\n"
            "Open the Dolby On app on your device and try again.",
            fg=typer.colors.RED, err=True
        )
        raise typer.Exit(1)


@app.command()
def status():
    """Check ADB connection and device status."""
    ctx.ensure()
    status_use_case = GetDeviceStatusUseCase(ctx.adb, CONFIG)
    result = status_use_case.execute()
    typer.secho(f"ADB path: {result['adb_path']}", fg=typer.colors.GREEN)
    typer.secho(f"Foreground app: {result['foreground_package']}", fg=typer.colors.GREEN)
    if result["is_dolby_foreground"]:
        typer.secho("Dolby On is in the foreground.", fg=typer.colors.GREEN)
    else:
        typer.secho("Dolby On is NOT in the foreground.", fg=typer.colors.YELLOW)


@app.command()
def list(
    all: bool = typer.Option(False, "--all", help="Scroll through all pages to list every track"),
    save_xml: Optional[str] = typer.Option(None, "--save-xml", help="Save raw UI XML to a file (single page)"),
    save_xml_folder: Optional[str] = typer.Option(None, "--save-xml-folder", help="Save raw UI XML for each page to a folder"),
    verbose: bool = typer.Option(False, "--verbose", "-v", help="Show each track as it is listed"),
):
    """List all tracks in the Dolby On library."""
    ctx.ensure()
    _require_dolby_foreground()

    from infrastructure.reporting import RichTrackListPresenter
    presenter = RichTrackListPresenter(verbose=verbose)

    list_use_case = ListTracksUseCase(
        ctx.adb, ctx.dolby, ctx.ui, CONFIG, presenter=presenter
    )
    result = list_use_case.execute(
        scroll_all=all,
        save_xml_path=save_xml,
        save_xml_folder=save_xml_folder,
    )

    if not result.tracks:
        typer.secho("No tracks found in library.", fg=typer.colors.YELLOW)
        return

    presenter.present_final(result.tracks, result.total_pages)


@app.command()
def dump(
    force: bool = typer.Option(False, "--force", "-f", help="Dump UI even if Dolby On is not in foreground"),
):
    """Dump raw UI XML to stdout for debugging."""
    ctx.ensure()
    if not force:
        _require_dolby_foreground()
    typer.echo("Dumping UI...", nl=False)
    try:
        xml = ctx.adb.dump_ui()
        typer.secho(" OK", fg=typer.colors.GREEN)
        typer.echo(xml)
    except Exception as e:
        typer.secho(f"Failed: {e}", fg=typer.colors.RED, err=True)
        raise typer.Exit(1)


@app.command()
def export(
    index: Optional[int] = typer.Option(None, "--index", "-i", help="Export a specific track by index"),
    all: bool = typer.Option(False, "--all", "-a", help="Export all tracks"),
    delete_after: bool = typer.Option(False, "--delete-after", help="Delete track after successful export"),
    rom: Optional[str] = typer.Option(None, "--rom", help="Force save dialog type: xiaomi or oppo"),
):
    """Export tracks to Google Drive."""
    ctx.ensure()
    _require_dolby_foreground()
    console = Console()

    if not index and not all:
        typer.secho("Specify --index <N> or --all", fg=typer.colors.YELLOW, err=True)
        raise typer.Exit(1)

    list_use_case = ListTracksUseCase(ctx.adb, ctx.dolby, ctx.ui, CONFIG)
    result = list_use_case.execute(scroll_all=False)
    if not result.tracks:
        typer.secho("No tracks found.", fg=typer.colors.YELLOW)
        raise typer.Exit(1)

    export_use_case = ExportTrackUseCase(ctx.adb, ctx.ui, ctx.dolby, ctx.coords, CONFIG, rom=rom, delete_after=delete_after)
    delete_use_case = DeleteTrackUseCase(ctx.adb, ctx.dolby, ctx.coords, CONFIG)

    targets = [result.tracks[index - 1]] if index else result.tracks

    console.print(Panel("[bold cyan]Dolby On Export[/bold cyan]", expand=False))

    for i, track in enumerate(targets, 1):
        console.print(f"[dim][[/dim][cyan]{i}/{len(targets)}[/cyan][dim]][/dim] [bold]{track.title}[/bold]", end="")
        exp_result = export_use_case.execute(track)
        if exp_result.is_success:
            console.print(" [green]OK[/green]")
        else:
            console.print(f" [red]FAIL: {exp_result.error}[/red]")


@app.command()
def delete(
    index: int = typer.Option(..., "--index", "-i", help="Delete a specific track by index"),
    force: bool = typer.Option(False, "--force", "-f", help="Skip confirmation prompt"),
):
    """Delete a track from the Dolby On library."""
    ctx.ensure()
    _require_dolby_foreground()

    list_use_case = ListTracksUseCase(ctx.adb, ctx.dolby, ctx.ui, CONFIG)
    result = list_use_case.execute(scroll_all=False)
    if not result.tracks:
        typer.secho("No tracks found.", fg=typer.colors.YELLOW)
        raise typer.Exit(1)

    if index < 1 or index > len(result.tracks):
        typer.secho(f"Track index out of range (1-{len(result.tracks)})", fg=typer.colors.RED, err=True)
        raise typer.Exit(1)

    track = result.tracks[index - 1]

    if not force:
        confirmed = typer.confirm(f"Delete track: {track.title}?")
        if not confirmed:
            typer.echo("Aborted.")
            raise typer.Exit(0)

    delete_use_case = DeleteTrackUseCase(ctx.adb, ctx.dolby, ctx.coords, CONFIG)
    del_result = delete_use_case.execute(track)

    if del_result.is_success:
        typer.secho(f"[OK] Deleted: {track.title}", fg=typer.colors.GREEN)
    else:
        typer.secho(f"[FAIL] {del_result.error}", fg=typer.colors.RED, err=True)
        raise typer.Exit(1)


@app.command()
def export_all(
    delete_after: bool = typer.Option(False, "--delete-after", help="Delete track after successful export"),
    rom: Optional[str] = typer.Option(None, "--rom", help="Force save dialog type: xiaomi or oppo"),
):
    """Export all tracks and show summary."""
    ctx.ensure()
    _require_dolby_foreground()
    console = Console()

    list_use_case = ListTracksUseCase(ctx.adb, ctx.dolby, ctx.ui, CONFIG)
    result = list_use_case.execute(scroll_all=True)
    if not result.tracks:
        typer.secho("No tracks found.", fg=typer.colors.YELLOW)
        raise typer.Exit(1)

    console.print(Panel("[bold cyan]Dolby On Export All[/bold cyan]", expand=False))
    console.print(f"[dim]Found [cyan]{len(result.tracks)}[/cyan] track(s)[/dim]\n")

    export_use_case = ExportTrackUseCase(ctx.adb, ctx.ui, ctx.dolby, ctx.coords, CONFIG, rom=rom, delete_after=delete_after)
    delete_use_case = DeleteTrackUseCase(ctx.adb, ctx.dolby, ctx.coords, CONFIG)

    tracks = list(result.tracks)
    processed = succeeded = failed = 0
    failed_tracks = []

    with Progress(
        TextColumn("[progress.description]{task.description}"),
        BarColumn(),
        TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
        console=console,
    ) as progress:
        task = progress.add_task("[cyan]Exporting...", total=len(result.tracks))

        while tracks:
            current = tracks[0]
            processed += 1
            progress.update(task, description=f"[cyan]{current.title[:30]}[/cyan]" if len(current.title) > 30 else f"[cyan]{current.title}[/cyan]", advance=1)

            exp_result = export_use_case.execute(current)
            if not exp_result.is_success:
                failed += 1
                failed_tracks.append({"title": current.title, "reason": f"Export: {exp_result.error}"})
                _rescan(tracks)
                progress.update(task, advance=-1)
                continue

            if delete_after:
                del_result = delete_use_case.execute(current)
                if not del_result.is_success:
                    failed += 1
                    failed_tracks.append({"title": current.title, "reason": f"Delete: {del_result.error}"})
                    _rescan(tracks)
                    progress.update(task, advance=-1)
                    continue

            succeeded += 1
            _rescan(tracks)

    console.print()
    summary_table = Table(box=box.ROUNDED, show_header=False, expand=False)
    summary_table.add_column("Label", style="bold")
    summary_table.add_column("Value")
    summary_table.add_row("Processed", str(processed))
    summary_table.add_row("[green]Succeeded[/green]", str(succeeded))
    summary_table.add_row("[red]Failed[/red]", str(failed) if failed else "0")
    summary_table.add_row("Remaining in library", str(len(tracks)))
    console.print(summary_table)

    if failed_tracks:
        console.print("\n[red bold]Failed tracks:[/red bold]")
        for ft in failed_tracks:
            console.print(f"  [red]-[/red] {ft['title']}: [dim]{ft['reason']}[/dim]")


def _rescan(tracks: list) -> None:
    time.sleep(2)
    xml = ctx.adb.dump_ui()
    updated = ctx.dolby.get_track_list(xml)
    tracks.clear()
    tracks.extend(updated)


if __name__ == "__main__":
    app()