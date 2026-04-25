import time
from datetime import datetime
from typing import Optional

import typer

from domain.exceptions import AdbNotFoundError, ElementNotFoundError, ExportError, DeleteError
from infrastructure.adb import AdbClient
from infrastructure.ui import UiAutomator, DolbyAppHelper, Coordinates
from infrastructure.reporting import ReportGenerator
from application.use_cases import ExportTrackUseCase, DeleteTrackUseCase, ProcessAllTracksUseCase


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
    def __init__(self, device_serial: Optional[str] = None, verbose: bool = False, dry_run: bool = False):
        self.device_serial = device_serial
        self.verbose = verbose
        self.dry_run = dry_run
        self.adb_client: Optional[AdbClient] = None
        self.ui_automator: Optional[UiAutomator] = None
        self.dolby_app: Optional[DolbyAppHelper] = None
        self.coords: Optional[Coordinates] = None
        self.initialized = False

    def ensure(self) -> None:
        if self.initialized:
            return
        self.adb_client = AdbClient(CONFIG)
        try:
            if not self.adb_client.find_adb():
                raise AdbNotFoundError(self.adb_client._not_found_message())
        except AdbNotFoundError as e:
            typer.echo(f"[ERROR] {e}", err=True)
            raise typer.Exit(1)
        self.ui_automator = UiAutomator(self.adb_client, CONFIG)
        self.dolby_app = DolbyAppHelper(CONFIG)
        self.coords = Coordinates()
        self.initialized = True


ctx = AppContext()


def _make_export_use_case():
    return ExportTrackUseCase(ctx.adb_client, ctx.ui_automator, ctx.dolby_app, ctx.coords, CONFIG)


def _make_delete_use_case():
    return DeleteTrackUseCase(ctx.adb_client, ctx.dolby_app, ctx.coords, CONFIG)


def _require_dolby_foreground():
    pkg = ctx.adb_client.get_foreground_package()
    target = CONFIG["DolbyApp"]["Package"]
    if pkg != target:
        typer.secho(
            f"Dolby On ({target}) is not in the foreground.\n"
            f"Current foreground app: {pkg or 'unknown'}\n"
            "Open the Dolby On app on your device and try again.",
            fg=typer.colors.RED, err=True
        )
        raise typer.Exit(1)


@app.command()
def status():
    """Check ADB connection and device status."""
    ctx.ensure()
    _require_dolby_foreground()
    adb_path = ctx.adb_client.adb_path
    typer.secho(f"ADB path: {adb_path}", fg=typer.colors.GREEN)
    typer.secho(f"Foreground app: {ctx.adb_client.get_foreground_package()}", fg=typer.colors.GREEN)


@app.command()
def list():
    """List all tracks in the Dolby On library."""
    ctx.ensure()
    _require_dolby_foreground()
    typer.echo("Dumping library UI...")
    try:
        xml = ctx.adb_client.dump_ui()
    except Exception as e:
        typer.secho(f"Failed to dump UI: {e}", fg=typer.colors.RED, err=True)
        raise typer.Exit(1)
    tracks = ctx.dolby_app.get_track_list(xml)
    if not tracks:
        typer.secho("No tracks found in library.", fg=typer.colors.YELLOW)
        return
    typer.echo(f"\nFound {len(tracks)} track(s):\n")
    for t in tracks:
        typer.echo(f"  [{t.index:2}] {t.title}  ({t.duration})  {t.date}")


@app.command()
def dump():
    """Dump raw UI XML to stdout for debugging."""
    ctx.ensure()
    _require_dolby_foreground()
    typer.echo("Dumping UI...", nl=False)
    try:
        xml = ctx.adb_client.dump_ui()
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

    typer.echo("Dumping library UI...")
    try:
        xml = ctx.adb_client.dump_ui()
    except Exception as e:
        typer.secho(f"Failed to dump UI: {e}", fg=typer.colors.RED, err=True)
        raise typer.Exit(1)

    tracks = ctx.dolby_app.get_track_list(xml)
    if not tracks:
        typer.secho("No tracks found.", fg=typer.colors.YELLOW)
        raise typer.Exit(1)

    export_use_case = _make_export_use_case()
    delete_use_case = _make_delete_use_case()

    targets = [tracks[index - 1]] if index else tracks

    for track in targets:
        typer.echo(f"\nExporting: {track.title}...")
        result = export_use_case.execute(track)
        if result.is_success:
            typer.secho(f"  [OK] Exported: {track.title}", fg=typer.colors.GREEN)
            if delete_after:
                typer.echo(f"  Deleting after export...")
                del_result = delete_use_case.execute(track)
                if del_result.is_success:
                    typer.secho(f"  [OK] Deleted: {track.title}", fg=typer.colors.GREEN)
                else:
                    typer.secho(f"  [WARN] Delete failed: {del_result.error}", fg=typer.colors.YELLOW)
        else:
            typer.secho(f"  [FAIL] {result.error}", fg=typer.colors.RED, err=True)


@app.command()
def delete(
    index: int = typer.Option(..., "--index", "-i", help="Delete a specific track by index"),
    force: bool = typer.Option(False, "--force", "-f", help="Skip confirmation prompt"),
):
    """Delete a track from the Dolby On library."""
    ctx.ensure()
    _require_dolby_foreground()

    typer.echo("Dumping library UI...")
    try:
        xml = ctx.adb_client.dump_ui()
    except Exception as e:
        typer.secho(f"Failed to dump UI: {e}", fg=typer.colors.RED, err=True)
        raise typer.Exit(1)

    tracks = ctx.dolby_app.get_track_list(xml)
    if not tracks:
        typer.secho("No tracks found.", fg=typer.colors.YELLOW)
        raise typer.Exit(1)

    if index < 1 or index > len(tracks):
        typer.secho(f"Track index out of range (1-{len(tracks)})", fg=typer.colors.RED, err=True)
        raise typer.Exit(1)

    track = tracks[index - 1]

    if not force:
        confirmed = typer.confirm(f"Delete track: {track.title}?")
        if not confirmed:
            typer.echo("Aborted.")
            raise typer.Exit(0)

    delete_use_case = _make_delete_use_case()
    result = delete_use_case.execute(track)

    if result.is_success:
        typer.secho(f"[OK] Deleted: {track.title}", fg=typer.colors.GREEN)
    else:
        typer.secho(f"[FAIL] {result.error}", fg=typer.colors.RED, err=True)
        raise typer.Exit(1)


@app.command()
def export_all(
    delete_after: bool = typer.Option(False, "--delete-after", help="Delete track after successful export"),
):
    """Export all tracks and show summary."""
    ctx.ensure()
    _require_dolby_foreground()

    typer.echo("Dumping library UI...")
    try:
        xml = ctx.adb_client.dump_ui()
    except Exception as e:
        typer.secho(f"Failed to dump UI: {e}", fg=typer.colors.RED, err=True)
        raise typer.Exit(1)

    tracks = ctx.dolby_app.get_track_list(xml)
    if not tracks:
        typer.secho("No tracks found.", fg=typer.colors.YELLOW)
        raise typer.Exit(1)

    typer.echo(f"Found {len(tracks)} track(s). Starting export...\n")

    export_use_case = _make_export_use_case()
    delete_use_case = _make_delete_use_case()

    processed = succeeded = failed = 0
    failed_tracks = []

    while tracks:
        current = tracks[0]
        processed += 1

        typer.echo(f"[{processed}/{len(tracks)+processed-1}] {current.title}...", nl=False)

        export_result = export_use_case.execute(current)
        if not export_result.is_success:
            failed += 1
            failed_tracks.append({"title": current.title, "reason": f"Export: {export_result.error}"})
            typer.secho(f" FAIL", fg=typer.colors.RED)
            _rescan(tracks)
            continue

        if delete_after:
            delete_result = delete_use_case.execute(current)
            if not delete_result.is_success:
                failed += 1
                failed_tracks.append({"title": current.title, "reason": f"Delete: {delete_result.error}"})
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


def _rescan(tracks: list) -> None:
    time.sleep(2)
    xml = ctx.adb_client.dump_ui()
    updated = ctx.dolby_app.get_track_list(xml)
    tracks.clear()
    tracks.extend(updated)


if __name__ == "__main__":
    app()