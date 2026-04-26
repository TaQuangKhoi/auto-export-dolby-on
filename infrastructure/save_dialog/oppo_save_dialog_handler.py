from .base_handler import BaseSaveDialogHandler


class OppoSaveDialogHandler(BaseSaveDialogHandler):
    def detect(self, xml_string: str) -> bool:
        if not xml_string:
            return False
        if self._app.find_element(xml_string, text="Drive"):
            return False
        oppo_indicators = [
            "oplus:id/resolver_pager",
            "Share via \"Nearby Share\"",
            "com.oplus.widget.OplusViewPager",
            "resolver_item_layout",
            "oplus_resolver_open_scan_icon",
        ]
        for indicator in oppo_indicators:
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

        save_targets = [
            ("text", "Save to Files"),
            ("text", "Files by Google"),
            ("text", "Download"),
        ]
        for attr, value in save_targets:
            if attr == "text":
                if self._tap_element(save_dialog_xml, text=value):
                    self._sleep(3)
                    return True
            else:
                if self._tap_element(save_dialog_xml, resource_id=value):
                    self._sleep(3)
                    return True

        first_item = self._find_first_clickable_item(save_dialog_xml)
        if first_item:
            center = self._coords.bounds_to_center(first_item["bounds"])
            self._adb.tap_at(*center)
            self._sleep(3)
            return True

        return False

    def _find_first_clickable_item(self, xml_string: str) -> dict | None:
        import xml.etree.ElementTree as ET
        try:
            root = ET.fromstring(xml_string)
            items = []
            for node in root.iter("node"):
                is_clickable = node.get("clickable", "false") == "true"
                bounds = node.get("bounds", "")
                is_valid_bounds = bounds and bounds != "[0,0][0,0]"
                if is_clickable and is_valid_bounds:
                    rect = self._parse_bounds(bounds)
                    if rect and rect[2] > 0 and rect[3] > 0:
                        items.append({"bounds": bounds, "area": (rect[2] - rect[0]) * (rect[3] - rect[1])})
            items.sort(key=lambda x: x["area"], reverse=True)
            return items[0] if items else None
        except Exception:
            return None

    def _parse_bounds(self, bounds_str: str) -> tuple | None:
        import re
        match = re.search(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', bounds_str)
        if match:
            return (int(match.group(1)), int(match.group(2)), int(match.group(3)), int(match.group(4)))
        return None