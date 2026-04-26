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

        dialog_xml = self._wait_for_dialog(config["WaitTimes"]["ExportMaxWait"])
        if not dialog_xml:
            return False

        return self._tap_save_target(dialog_xml)

    def handle_save_dialog_with_xml(self, adb_client, ui_automator, coords, config: dict, dialog_xml: str) -> bool:
        self._adb = adb_client
        self._ui = ui_automator
        self._coords = coords
        self._config = config

        return self._tap_save_target(dialog_xml)

    def _tap_save_target(self, dialog_xml: str) -> bool:
        print(f"\033[90m[OPPO] _tap_save_target called, XML length: {len(dialog_xml)}\033[0m")
        save_targets = [
            "Save to Files",
            "Files by Google",
            "Download",
        ]
        for value in save_targets:
            elem = self._app.find_element(dialog_xml, text=value)
            print(f"\033[90m[OPPO] Looking for '{value}': {'FOUND' if elem else 'NOT FOUND'}\033[0m")
            if elem:
                center = self._coords.bounds_to_center(elem["bounds"])
                print(f"\033[90m[OPPO] Tapping '{value}' at {center}\033[0m")
                self._adb.tap_at(*center)
                self._sleep(3)
                return True

        print("\033[90m[OPPO] No standard target found, trying fallback...\033[0m")
        first_item = self._find_first_clickable_item(dialog_xml)
        if first_item:
            center = self._coords.bounds_to_center(first_item["bounds"])
            print(f"\033[90m[OPPO] Tapping fallback item at {center}\033[0m")
            self._adb.tap_at(*center)
            self._sleep(3)
            return True

        print("\033[90m[OPPO] No clickable element found\033[0m")
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