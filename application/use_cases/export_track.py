from domain.entities import Track, ExportResult
from domain.exceptions import ElementNotFoundError, ExportError
from infrastructure.save_dialog import SaveDialogDetector


class ExportTrackUseCase:
    def __init__(
        self,
        adb_client,
        ui_automator,
        dolby_app,
        coordinates,
        config: dict,
    ):
        self._adb = adb_client
        self._ui = ui_automator
        self._app = dolby_app
        self._coords = coordinates
        self._config = config

    def execute(self, track: Track) -> ExportResult:
        try:
            return self._do_export(track)
        except ElementNotFoundError as e:
            return ExportResult(success=False, step="Export", error=str(e), track_title=track.title)
        except ExportError as e:
            return ExportResult(success=False, step="Export", error=str(e), track_title=track.title)
        except Exception as e:
            return ExportResult(success=False, step="Export", error=f"Unexpected: {e}", track_title=track.title)

    def _do_export(self, track: Track) -> ExportResult:
        res_ids = self._config["DolbyApp"]["ResourceIds"]
        self._log("[1/8] Dump UI")

        xml = self._adb.dump_ui()

        if self._app.is_list_view(xml):
            self._log("[2/8] List view detected — tapping track item")
            track_item = self._app.find_track_item_in_list(xml, track)
            if not track_item:
                raise ElementNotFoundError(f"Track item not found in list: {track.title}")
            center = self._coords.bounds_to_center(track_item["bounds"])
            self._adb.tap_at(*center)
            self._sleep(self._config["WaitTimes"]["ScreenLoad"])
            xml = self._adb.dump_ui()
        else:
            self._log("[2/8] Detail view detected — skip tap")

        self._log("[3/8] Looking for Share button")
        share_btn = self._app.find_element(xml, resource_id=res_ids["ShareButton"])
        if not share_btn:
            raise ElementNotFoundError("Share button not found — not in detail view")

        center = self._coords.bounds_to_center(share_btn["bounds"])
        self._adb.tap_at(*center)
        self._log("[4/8] Tapped Share button — waiting for popup")

        self._sleep(self._config["WaitTimes"]["PopupAppear"])

        xml = self._adb.dump_ui()
        self._log("[5/8] Looking for Export Lossless option")
        export_btn = self._app.find_element(xml, resource_id=res_ids["ExportLossless"])
        if not export_btn:
            raise ElementNotFoundError("Export Lossless button not found")

        center = self._coords.bounds_to_center(export_btn["bounds"])
        self._adb.tap_at(*center)
        self._log("[6/8] Tapped Export Lossless — detecting save dialog type")

        detector = SaveDialogDetector(self._adb, self._ui, self._app, self._coords, self._config)
        success = detector.detect_and_handle()
        if not success:
            raise ExportError("Save dialog handling failed")

        self._sleep(self._config["WaitTimes"]["ReturnToDetail"])

        self._adb.press_back()
        self._sleep(1)
        self._log("[OK] Export complete — returned to list")

        return ExportResult(success=True, step="Export", track_title=track.title)

    def _log(self, msg: str) -> None:
        print(f"\033[90m{msg}\033[0m")

    def _sleep(self, seconds: float) -> None:
        import time
        time.sleep(seconds)