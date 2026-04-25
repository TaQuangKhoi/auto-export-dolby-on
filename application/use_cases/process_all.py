from domain.entities import Track, ProcessResult
from application.use_cases.export_track import ExportTrackUseCase
from application.use_cases.delete_track import DeleteTrackUseCase


class ProcessAllTracksUseCase:
    def __init__(
        self,
        export_use_case: ExportTrackUseCase,
        delete_use_case: DeleteTrackUseCase,
        adb_client,
        dolby_app,
        config: dict,
    ):
        self._export = export_use_case
        self._delete = delete_use_case
        self._adb = adb_client
        self._app = dolby_app
        self._config = config

    def execute(self, initial_tracks: list[Track]) -> ProcessResult:
        tracks = list(initial_tracks)
        processed = 0
        succeeded = 0
        failed = 0
        failed_tracks = []

        while tracks:
            current = tracks[0]
            processed += 1

            export_result = self._export.execute(current)
            if not export_result.is_success:
                failed += 1
                failed_tracks.append({"title": current.title, "reason": f"Export: {export_result.error}"})
                self._rescan_and_continue(tracks)
                continue

            delete_result = self._delete.execute(current)
            if not delete_result.is_success:
                failed += 1
                failed_tracks.append({"title": current.title, "reason": f"Delete: {delete_result.error}"})
                self._rescan_and_continue(tracks)
                continue

            succeeded += 1
            self._rescan_and_continue(tracks)

        return ProcessResult(
            success=(failed == 0),
            processed=processed,
            succeeded=succeeded,
            failed=failed,
            failed_tracks=failed_tracks,
        )

    def _rescan_and_continue(self, tracks: list) -> None:
        import time
        time.sleep(2)
        xml = self._adb.dump_ui()
        updated = self._app.get_track_list(xml)
        tracks.clear()
        tracks.extend(updated)