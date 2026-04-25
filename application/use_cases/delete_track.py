from domain.entities import Track, ExportResult
from domain.exceptions import ElementNotFoundError, DeleteError


class DeleteTrackUseCase:
    def __init__(
        self,
        adb_client,
        dolby_app,
        coordinates,
        config: dict,
    ):
        self._adb = adb_client
        self._app = dolby_app
        self._coords = coordinates
        self._config = config

    def execute(self, track: Track) -> ExportResult:
        try:
            return self._do_delete(track)
        except ElementNotFoundError as e:
            return ExportResult(success=False, step="Delete", error=str(e), track_title=track.title)
        except DeleteError as e:
            return ExportResult(success=False, step="Delete", error=str(e), track_title=track.title)
        except Exception as e:
            return ExportResult(success=False, step="Delete", error=f"Unexpected: {e}", track_title=track.title)

    def _do_delete(self, track: Track) -> ExportResult:
        res_ids = self._config["DolbyApp"]["ResourceIds"]

        self._sleep(self._config["WaitTimes"]["ScreenLoad"])

        xml = self._adb.dump_ui()
        more_btn = self._app.find_element(xml, resource_id=res_ids["MoreButton"])
        if not more_btn:
            raise ElementNotFoundError("More button not found")

        center = self._coords.bounds_to_center(more_btn["bounds"])
        self._adb.tap_at(*center)

        self._sleep(self._config["WaitTimes"]["PopupAppear"])

        xml = self._adb.dump_ui()
        delete_opt = self._app.find_element(xml, text="Delete")
        if not delete_opt:
            delete_opt = self._app.find_element(xml, content_desc="Delete")
        if not delete_opt:
            delete_opt = self._app.find_element(xml, resource_id=res_ids["DeleteOption"])
        if not delete_opt:
            raise ElementNotFoundError("Delete option not found")

        center = self._coords.bounds_to_center(delete_opt["bounds"])
        self._adb.tap_at(*center)

        self._sleep(self._config["WaitTimes"]["DeleteConfirm"])

        xml = self._adb.dump_ui()
        confirm_btn = self._app.find_element(xml, text="Delete")
        if not confirm_btn:
            confirm_btn = self._app.find_element(xml, text="OK")
        if not confirm_btn:
            confirm_btn = self._app.find_element(xml, text="Yes")
        if not confirm_btn:
            confirm_btn = self._app.find_element(xml, resource_id=res_ids["ConfirmDeleteButton"])
        if not confirm_btn:
            raise ElementNotFoundError("Confirm Delete button not found")

        center = self._coords.bounds_to_center(confirm_btn["bounds"])
        self._adb.tap_at(*center)

        self._sleep(2)

        return ExportResult(success=True, step="Delete", track_title=track.title)

    def _sleep(self, seconds: float) -> None:
        import time
        time.sleep(seconds)