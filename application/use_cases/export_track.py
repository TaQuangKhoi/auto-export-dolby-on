from domain.entities import Track, ExportResult
from domain.exceptions import ElementNotFoundError, ExportError


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

        xml = self._adb.dump_ui()
        share_btn = self._app.find_element(xml, resource_id=res_ids["ShareButton"])
        if not share_btn:
            raise ElementNotFoundError("Share button not found")

        center = self._coords.bounds_to_center(share_btn["bounds"])
        self._adb.tap_at(*center)

        self._sleep(self._config["WaitTimes"]["PopupAppear"])

        xml = self._adb.dump_ui()
        export_btn = self._app.find_element(xml, resource_id=res_ids["ExportLossless"])
        if not export_btn:
            raise ElementNotFoundError("Export Lossless button not found")

        center = self._coords.bounds_to_center(export_btn["bounds"])
        self._adb.tap_at(*center)

        save_dialog_xml = self._ui.wait_for_export_completion(
            max_wait=self._config["WaitTimes"]["ExportMaxWait"]
        )
        if not save_dialog_xml:
            raise ExportError("Export timed out — Save Dialog did not appear")

        drive_btn = self._app.find_element(save_dialog_xml, text="Drive")
        if not drive_btn:
            drive_btn = self._app.find_element(save_dialog_xml, content_desc="Drive")
        if not drive_btn:
            raise ElementNotFoundError("Drive button not found")

        center = self._coords.bounds_to_center(drive_btn["bounds"])
        self._adb.tap_at(*center)

        self._sleep(3)

        drive_screen_xml = self._adb.dump_ui()
        save_btn = self._app.find_element(
            drive_screen_xml, resource_id="com.google.android.apps.docs:id/save_button"
        )
        if not save_btn:
            save_btn = self._app.find_element(drive_screen_xml, text="Save")
        if not save_btn:
            raise ElementNotFoundError("Save button not found")

        center = self._coords.bounds_to_center(save_btn["bounds"])
        self._adb.tap_at(*center)

        self._sleep(self._config["WaitTimes"]["ReturnToDetail"])

        return ExportResult(success=True, step="Export", track_title=track.title)

    def _sleep(self, seconds: float) -> None:
        import time
        time.sleep(seconds)