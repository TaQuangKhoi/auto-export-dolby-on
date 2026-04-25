import re
import time
from typing import Any
import xml.etree.ElementTree as ET

from domain.exceptions import UiDumpError


class UiAutomator:
    def __init__(self, adb_client, config: dict):
        self._adb = adb_client
        self._config = config

    def parse_elements(self, xml_string: str) -> list[dict]:
        if not xml_string or not xml_string.strip():
            return []
        try:
            root = ET.fromstring(xml_string)
            elements = []
            self._collect_elements(root, elements)
            return elements
        except ET.ParseError as e:
            raise UiDumpError(f"Failed to parse UI XML: {e}")

    def _collect_elements(self, node: ET.Element, elements: list[dict]) -> None:
        if node.tag == "node":
            text = node.get("text", "")
            content_desc = node.get("content-desc", "")
            resource_id = node.get("resource-id", "")
            class_name = node.get("class", "")
            bounds = node.get("bounds", "")

            if text or content_desc or resource_id:
                elements.append({
                    "class": class_name,
                    "text": text,
                    "content_desc": content_desc,
                    "resource_id": resource_id,
                    "bounds": bounds,
                })
            for child in node:
                self._collect_elements(child, elements)

    def find_element(self, xml_string: str, **attrs) -> dict | None:
        for elem in self.parse_elements(xml_string):
            match = True
            for key, value in attrs.items():
                elem_val = elem.get(key.replace("resource_id", "resource_id").replace("text", "text").replace("content_desc", "content_desc"))
                if elem_val != value:
                    match = False
                    break
            if match:
                return elem
        return None

    def wait_for_export_completion(self, max_wait: int = 300) -> str | None:
        wait_times = self._config.get("WaitTimes", {})
        interval = wait_times.get("ExportCheckInterval", 2)
        start = time.time()

        while (time.time() - start) < max_wait:
            try:
                xml = self._adb.dump_ui()
                if self._is_save_dialog_visible(xml):
                    elapsed = round(time.time() - start, 1)
                    return xml
            except Exception:
                pass
            time.sleep(interval)

        return None

    def _is_save_dialog_visible(self, xml: str) -> bool:
        return bool(
            re.search(r'com\.android\.documentsui', xml) or
            re.search(r'text="Save"|content-desc="Save"', xml) or
            re.search(r'text="Drive"|content-desc="Drive"', xml)
        )