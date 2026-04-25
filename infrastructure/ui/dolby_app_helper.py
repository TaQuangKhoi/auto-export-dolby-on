import re
import xml.etree.ElementTree as ET
from domain.entities import Track


class DolbyAppHelper:
    def __init__(self, config: dict):
        self._config = config

    def get_track_list(self, xml_string: str, start_index: int = 1, seen_track_ids: set[str] | None = None) -> list[Track]:
        if not xml_string:
            return []
        if seen_track_ids is None:
            seen_track_ids = set()

        try:
            root = ET.fromstring(xml_string)
            dolby_cfg = self._config.get("DolbyApp", {})
            res_ids = dolby_cfg.get("ResourceIds", {})
            recycler_id = res_ids.get("RecyclerView", "")
            track_item_id = res_ids.get("TrackItem", "")
            title_id = res_ids.get("Title", "")
            date_id = res_ids.get("Date", "")
            time_id = res_ids.get("Time", "")

            recycler = root.find(f".//node[@resource-id='{recycler_id}']")
            if recycler is None:
                return []

            tracks = []
            index = start_index
            for item in recycler.findall(f".//node[@resource-id='{track_item_id}']"):
                content_desc = item.get("content-desc", "")

                title_node = item.find(f".//node[@resource-id='{title_id}']")
                date_node = item.find(f".//node[@resource-id='{date_id}']")
                time_node = item.find(f".//node[@resource-id='{time_id}']")

                title = title_node.get("text", "(No Title)") if title_node is not None else "(No Title)"
                date = date_node.get("text", "") if date_node is not None else ""
                duration = time_node.get("text", "") if time_node is not None else ""

                track_id = f"{title}|{date}|{duration}"
                if track_id in seen_track_ids:
                    continue
                seen_track_ids.add(track_id)

                track = Track(
                    index=index,
                    title=title,
                    date=date,
                    duration=duration,
                    bounds=item.get("bounds", ""),
                    content_desc=content_desc,
                )
                tracks.append(track)
                index += 1
            return tracks
        except ET.ParseError:
            return []

    def has_more_items_below(self, xml_string: str) -> bool:
        if not xml_string:
            return False
        try:
            root = ET.fromstring(xml_string)
            dolby_cfg = self._config.get("DolbyApp", {})
            res_ids = dolby_cfg.get("ResourceIds", {})
            recycler_id = res_ids.get("RecyclerView", "")
            recycler = root.find(f".//node[@resource-id='{recycler_id}']")
            if recycler is None:
                return False

            bounds = recycler.get("bounds", "")
            if not bounds:
                return False

            match = re.search(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', bounds)
            if not match:
                return False

            recycler_bottom = int(match.group(4))

            last_item = recycler.findall(f".//node[@resource-id='{res_ids.get('TrackItem', '')}']")[-1:]
            if not last_item:
                return False

            item_bounds = last_item[0].get("bounds", "")
            item_match = re.search(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', item_bounds)
            if not item_match:
                return False

            last_item_bottom = int(item_match.group(4))
            return last_item_bottom < recycler_bottom - 50

        except Exception:
            return False

    def find_element(self, xml_string: str, resource_id: str = None, text: str = None, content_desc: str = None) -> dict | None:
        if not xml_string:
            return None
        try:
            root = ET.fromstring(xml_string)
            for node in root.iter("node"):
                rid = node.get("resource-id")
                txt = node.get("text")
                cd = node.get("content-desc")
                if resource_id and rid == resource_id:
                    return self._node_to_dict(node)
                if text and txt == text:
                    return self._node_to_dict(node)
                if content_desc and cd == content_desc:
                    return self._node_to_dict(node)
            return None
        except ET.ParseError:
            return None

    def _node_to_dict(self, node: ET.Element) -> dict:
        return {
            "bounds": node.get("bounds", ""),
            "text": node.get("text", ""),
            "content_desc": node.get("content-desc", ""),
            "resource_id": node.get("resource-id", ""),
            "class": node.get("class", ""),
        }