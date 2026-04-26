from abc import ABC
import time
from domain.exceptions import ElementNotFoundError, ExportError


class BaseSaveDialogHandler(ABC):
    def __init__(self, adb_client, ui_automator, dolby_app, coords, config: dict):
        self._adb = adb_client
        self._ui = ui_automator
        self._app = dolby_app
        self._coords = coords
        self._config = config

    def _sleep(self, seconds: float) -> None:
        time.sleep(seconds)

    def _wait_for_dialog(self, max_wait: int) -> str | None:
        return self._ui.wait_for_export_completion(max_wait=max_wait)

    def _tap_element(self, xml: str, **attrs) -> bool:
        elem = self._app.find_element(xml, **attrs)
        if not elem:
            return False
        center = self._coords.bounds_to_center(elem["bounds"])
        self._adb.tap_at(*center)
        return True