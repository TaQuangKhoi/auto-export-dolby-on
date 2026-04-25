import re


class Coordinates:
    def bounds_to_center(self, bounds: str) -> tuple[int, int]:
        match = re.search(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', bounds)
        if not match:
            raise ValueError(f"Invalid bounds format: {bounds}")
        x1, y1, x2, y2 = map(int, match.groups())
        return int((x1 + x2) / 2), int((y1 + y2) / 2)