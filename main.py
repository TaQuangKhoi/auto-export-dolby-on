import sys
import time
from typing import Optional

import typer
from rich.console import Console
from rich.table import Table
from rich import box

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

    console = Console()

    def on_page(page_num: int, tracks: list, is_last: bool):
        if not verbose:
            return
        if not tracks:
            console.print(f"  [dim]End of list reached[/dim]")
            sys.stdout.flush()
            return
        for t in tracks:
            idx = f"[cyan]{t.index:2}[/cyan]"
            title = f"[bold]{t.title}[/bold]" if t.title != "(No Title)" else f"[dim](No Title)[/dim]"
            dur = f"[yellow]({t.duration})[/yellow]" if t.duration else "[dim]()[/dim]"
            date = f"[green]{t.date}[/green]"
            console.print(f"  {idx}] {title}  {dur}  {date}")
            sys.stdout.flush()

    list_use_case = ListTracksUseCase(ctx.adb, ctx.dolby, ctx.ui, CONFIG)
    result = list_use_case.execute(
        scroll_all=all,
        save_xml_path=save_xml,
        save_xml_folder=save_xml_folder,
        on_page=on_page,
    )

    if not result.tracks:
        typer.secho("No tracks found in library.", fg=typer.colors.YELLOW)
        return

    table = Table(title=f"[bold]Dolby On Library[/bold]  —  {len(result.tracks)} track(s) found", box=box.ROUNDED)
    table.add_column("#", style="cyan", width=4, justify="right")
    table.add_column("Title", style="bold")
    table.add_column("Duration", style="yellow", width=10, justify="center")
    table.add_column("Date", style="green")

    for t in result.tracks:
        title = t.title if t.title != "(No Title)" else "(No Title)"
        duration = t.duration or "—"
        date = t.date or "—"
        table.add_row(str(t.index), title, f"({duration})", date)

    console.print()
    console.print(table)


@app.command()
def dump():
    """Dump raw UI XML to stdout for debugging."""
    ctx.ensure()
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
):
    """Export tracks to Google Drive."""
    ctx.ensure()
    _require_dolby_foreground()

    if not index and not all:
        typer.secho("Specify --index <N> or --all", fg=typer.colors.YELLOW, err=True)
        raise typer.Exit(1)

    list_use_case = ListTracksUseCase(ctx.adb, ctx.dolby, ctx.ui, CONFIG)
    result = list_use_case.execute(scroll_all=False)
    if not result.tracks:
        typer.secho("No tracks found.", fg=typer.colors.YELLOW)
        raise typer.Exit(1)

    export_use_case = ExportTrackUseCase(ctx.adb, ctx.ui, ctx.dolby, ctx.coords, CONFIG)
    delete_use_case = DeleteTrackUseCase(ctx.adb, ctx.dolby, ctx.coords, CONFIG)

    targets = [result.tracks[index - 1]] if index else result.tracks

    for track in targets:
        typer.echo(f"\nExporting: {track.title}...")
        exp_result = export_use_case.execute(track)
        if exp_result.is_success:
            typer.secho(f"  [OK] Exported: {track.title}", fg=typer.colors.GREEN)
            if delete_after:
                typer.echo("  Deleting after export...")
                del_result = delete_use_case.execute(track)
                if del_result.is_success:
                    typer.secho(f"  [OK] Deleted: {track.title}", fg=typer.colors.GREEN)
                else:
                    typer.secho(f"  [WARN] Delete failed: {del_result.error}", fg=typer.colors.YELLOW)
        else:
            typer.secho(f"  [FAIL] {exp_result.error}", fg=typer.colors.RED, err=True)


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
):
    """Export all tracks and show summary."""
    ctx.ensure()
    _require_dolby_foreground()

    list_use_case = ListTracksUseCase(ctx.adb, ctx.dolby, ctx.ui, CONFIG)
    result = list_use_case.execute(scroll_all=True)
    if not result.tracks:
        typer.secho("No tracks found.", fg=typer.colors.YELLOW)
        raise typer.Exit(1)

    typer.echo(f"Found {len(result.tracks)} track(s). Starting export...\n")

    export_use_case = ExportTrackUseCase(ctx.adb, ctx.ui, ctx.dolby, ctx.coords, CONFIG)
    delete_use_case = DeleteTrackUseCase(ctx.adb, ctx.dolby, ctx.coords, CONFIG)

    tracks = list(result.tracks)
    processed = succeeded = failed = 0
    failed_tracks = []

    while tracks:
        current = tracks[0]
        processed += 1

        typer.echo(f"[{processed}/{len(result.tracks)}] {current.title}...", nl=False)

        exp_result = export_use_case.execute(current)
        if not exp_result.is_success:
            failed += 1
            failed_tracks.append({"title": current.title, "reason": f"Export: {exp_result.error}"})
            typer.secho(f" FAIL", fg=typer.colors.RED)
            _rescan(tracks)
            continue

        if delete_after:
            del_result = delete_use_case.execute(current)
            if not del_result.is_success:
                failed += 1
                failed_tracks.append({"title": current.title, "reason": f"Delete: {del_result.error}"})
                typer.secho(f" OK but DELETE FAIL", fg=typer.colors.YELLOW)
                _rescan(tracks)
                continue

        succeeded += 1
        typer.secho(f" OK", fg=typer.colors.GREEN)
        _rescan(tracks)

    typer.echo(f"\n{'='*50}")
    typer.echo(f"  Processed: {processed}")
    typer.secho(f"  Succeeded: {succeeded}", fg=typer.colors.GREEN)
    typer.secho(f"  Failed:    {failed}", fg=typer.colors.RED if failed else typer.colors.WHITE)

    if failed_tracks:
        typer.echo("\nFailed tracks:")
        for ft in failed_tracks:
            typer.echo(f"  - {ft['title']}: {ft['reason']}")

    typer.secho(f"\nRemaining tracks in library: {len(tracks)}", fg=typer.colors.CYAN)


def _rescan(tracks: list) -> None:
    time.sleep(2)
    xml = ctx.adb.dump_ui()
    updated = ctx.dolby.get_track_list(xml)
    tracks.clear()
    tracks.extend(updated)


if __name__ == "__main__":
    app()