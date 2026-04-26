from .xiaomi_save_dialog_handler import XiaomiSaveDialogHandler
from .oppo_save_dialog_handler import OppoSaveDialogHandler


class SaveDialogDetector:
    def __init__(self, adb_client, ui_automator, dolby_app, coords, config: dict):
        self._adb = adb_client
        self._ui = ui_automator
        self._app = dolby_app
        self._coords = coords
        self._config = config
        self._handlers = [
            XiaomiSaveDialogHandler(adb_client, ui_automator, dolby_app, coords, config),
            OppoSaveDialogHandler(adb_client, ui_automator, dolby_app, coords, config),
        ]
        self._active_handler = None
        self._forced_handler_name: str | None = None

    def detect_and_handle(self) -> bool:
        print("\033[90m[Detector] Starting detect_and_handle\033[0m")
        if self._forced_handler_name:
            print(f"\033[90m[Detector] Using forced handler: {self._forced_handler_name}\033[0m")
            return self._use_handler(self._forced_handler_name)

        print("\033[90m[Detector] Waiting for dialog to appear...\033[0m")
        max_wait = self._config["WaitTimes"]["ExportMaxWait"]
        dialog_xml = self._ui.wait_for_export_completion(max_wait=max_wait)
        if not dialog_xml:
            print("\033[90m[Detector] ERROR: Dialog never appeared\033[0m")
            return False

        print(f"\033[90m[Detector] Dialog appeared! XML length: {len(dialog_xml)}\033[0m")
        for handler in self._handlers:
            if handler.detect(dialog_xml):
                self._active_handler = handler
                print(f"\033[90m[Detector] Detected: {handler.__class__.__name__}\033[0m")
                return handler.handle_save_dialog_with_xml(self._adb, self._ui, self._coords, self._config, dialog_xml)
        print("\033[90m[Detector] No handler matched dialog\033[0m")
        return False

    def _use_handler_with_xml(self, name: str, dialog_xml: str) -> bool:
        name_to_handler = {
            "xiaomi": XiaomiSaveDialogHandler(self._adb, self._ui, self._app, self._coords, self._config),
            "oppo": OppoSaveDialogHandler(self._adb, self._ui, self._app, self._coords, self._config),
        }
        handler = name_to_handler.get(name.lower())
        if handler:
            self._active_handler = handler
            return handler.handle_save_dialog_with_xml(self._adb, self._ui, self._coords, self._config, dialog_xml)
        return False

    def _use_handler(self, name: str) -> bool:
        print(f"\033[90m[Detector] _use_handler({name}): waiting for dialog...\033[0m")
        max_wait = self._config["WaitTimes"]["ExportMaxWait"]
        dialog_xml = self._ui.wait_for_export_completion(max_wait=max_wait)
        if not dialog_xml:
            print("\033[90m[Detector] ERROR: Dialog never appeared\033[0m")
            return False
        print(f"\033[90m[Detector] Dialog appeared! XML length: {len(dialog_xml)}\033[0m")
        return self._use_handler_with_xml(name, dialog_xml)

    def set_handler(self, handler_name: str) -> bool:
        name_to_handler = {
            "xiaomi": XiaomiSaveDialogHandler(self._adb, self._ui, self._app, self._coords, self._config),
            "oppo": OppoSaveDialogHandler(self._adb, self._ui, self._app, self._coords, self._config),
        }
        handler = name_to_handler.get(handler_name.lower())
        if handler:
            self._active_handler = handler
            self._forced_handler_name = handler_name.lower()
            return True
        return False