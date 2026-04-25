import time
from datetime import datetime

from domain.exceptions import AdbNotFoundError
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


def print_header():
    print("\n========================================")
    print("  DOLBY ON EXPORT AUTOMATION")
    print("========================================\n")


def print_step(step: str, msg: str):
    print(f"\n[STEP {step}] {msg}")


def print_track_header(processed: int, total: int, track):
    print(f"\n╔{'='*60}")
    print(f"║  TRACK {processed} of {total}")
    print(f"║  Title: {track.title}")
    print(f"║  Duration: {track.duration}")
    print(f"╚{'='*60}")


def print_result(success: bool, step: str, error: str = None):
    if success:
        print(f"  Track completed successfully!")
    else:
        print(f"  Failed at step: {step}")
        if error:
            print(f"     Error: {error}")


def print_summary(result):
    print("\n╔════════════════════════════════════════════════════════════")
    print("║  BATCH EXPORT COMPLETE!")
    print("╚════════════════════════════════════════════════════════════")
    print("\n========================================")
    print("  FINAL SUMMARY")
    print("========================================\n")
    print(f"Total tracks processed: {result.processed}")
    print(f"Successful exports: {result.succeeded}")
    print(f"Failed exports: {result.failed}")
    print(f"Remaining in library: {len(result.failed_tracks)}")

    if result.failed_tracks:
        print("\nFailed Tracks:")
        for ft in result.failed_tracks:
            print(f"  - {ft['title']}")
            print(f"    Reason: {ft['reason']}")


def run():
    print_header()

    adb_client = AdbClient(CONFIG)

    try:
        path = adb_client.find_adb()
        if not path:
            raise AdbNotFoundError(adb_client._not_found_message())
        print(f"ADB found: {adb_client.adb_path}")
    except AdbNotFoundError as e:
        print(f"Error: {e}")
        return 1

    ui_automator = UiAutomator(adb_client, CONFIG)
    dolby_app = DolbyAppHelper(CONFIG)
    coords = Coordinates()

    export_use_case = ExportTrackUseCase(adb_client, ui_automator, dolby_app, coords, CONFIG)
    delete_use_case = DeleteTrackUseCase(adb_client, dolby_app, coords, CONFIG)
    process_all_use_case = ProcessAllTracksUseCase(
        export_use_case, delete_use_case, adb_client, dolby_app, CONFIG
    )

    print("Waiting for app to stabilize...")
    time.sleep(CONFIG["WaitTimes"]["AppStabilize"])

    print_step(1, "Dumping Library Screen...")

    try:
        library_xml = adb_client.dump_ui()
    except Exception as e:
        print(f"Failed to get library screen UI dump: {e}")
        return 1

    tracks = dolby_app.get_track_list(library_xml)

    if not tracks:
        print("No tracks found in library. Exiting.")
        return 1

    total_tracks = len(tracks)
    print(f"Total tracks found: {total_tracks}")
    print(f"\nStarting batch export for all {total_tracks} tracks...")

    result = process_all_use_case.execute(tracks)

    print_summary(result)

    if CONFIG["EnableReport"]:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        report_path = f"dolby_export_report_{timestamp}.html"
        report_gen = ReportGenerator(CONFIG)
        report_gen.generate(report_path, tracks=tracks, timestamp=timestamp)

    return 0


if __name__ == "__main__":
    raise SystemExit(run())