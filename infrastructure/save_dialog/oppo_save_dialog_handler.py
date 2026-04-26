from .base_handler import BaseSaveDialogHandler


class OppoSaveDialogHandler(BaseSaveDialogHandler):
    def detect(self, xml_string: str) -> bool:
        if not xml_string:
            return False
        if self._app.find_element(xml_string, text="Drive"):
            return False
        oppo_save_indicators = [
            "com.android.internal:id/button1",
            "com.android.internal:id/button2",
            "android:id/button1",
            "android:id/button2",
            "JUST ONCE",
            "ALWAYS",
        ]
        for indicator in oppo_save_indicators:
            if "id" in indicator:
                elem = self._app.find_element(xml_string, resource_id=indicator)
                if elem:
                    return True
            else:
                elem = self._app.find_element(xml_string, text=indicator)
                if elem:
                    return True
        return False

    def handle_save_dialog(self, adb_client, ui_automator, coords, config: dict) -> bool:
        self._adb = adb_client
        self._ui = ui_automator
        self._coords = coords
        self._config = config

        max_wait = config["WaitTimes"]["ExportMaxWait"]
        save_dialog_xml = self._wait_for_dialog(max_wait)
        if not save_dialog_xml:
            return False

        save_options = [
            ("text", "JUST ONCE"),
            ("text", "ALWAYS"),
            ("text", "Save file"),
            ("resource_id", "com.android.internal:id/button1"),
            ("resource_id", "android:id/button1"),
            ("resource_id", "com.android.internal:id/button2"),
            ("resource_id", "android:id/button2"),
            ("text", "Save"),
        ]
        for attr, value in save_options:
            if attr == "text":
                if self._tap_element(save_dialog_xml, text=value):
                    return True
            else:
                if self._tap_element(save_dialog_xml, resource_id=value):
                    return True

        return False