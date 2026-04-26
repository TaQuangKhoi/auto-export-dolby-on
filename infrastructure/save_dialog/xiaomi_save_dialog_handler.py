from .base_handler import BaseSaveDialogHandler


class XiaomiSaveDialogHandler(BaseSaveDialogHandler):
    def detect(self, xml_string: str) -> bool:
        if not xml_string:
            return False
        drive_btn = self._app.find_element(xml_string, text="Drive")
        if drive_btn:
            return True
        drive_btn = self._app.find_element(xml_string, content_desc="Drive")
        return drive_btn is not None

    def handle_save_dialog(self, adb_client, ui_automator, coords, config: dict) -> bool:
        self._adb = adb_client
        self._ui = ui_automator
        self._coords = coords
        self._config = config

        max_wait = config["WaitTimes"]["ExportMaxWait"]
        save_dialog_xml = self._wait_for_dialog(max_wait)
        if not save_dialog_xml:
            return False

        drive_btn = self._app.find_element(save_dialog_xml, text="Drive")
        if not drive_btn:
            drive_btn = self._app.find_element(save_dialog_xml, content_desc="Drive")
        if not drive_btn:
            return False

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
            return False

        center = self._coords.bounds_to_center(save_btn["bounds"])
        self._adb.tap_at(*center)
        return True