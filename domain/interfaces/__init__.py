from abc import ABC, abstractmethod
from typing import Protocol


class IAdbClient(Protocol):
    @abstractmethod
    def find_adb(self) -> str | None:
        ...

    @abstractmethod
    def tap_at(self, x: int, y: int) -> None:
        ...

    @abstractmethod
    def swipe(self, x1: int, y1: int, x2: int, y2: int, duration_ms: int = 800) -> None:
        ...

    @abstractmethod
    def dump_ui(self) -> str:
        ...

    @abstractmethod
    def get_foreground_package(self) -> str | None:
        ...


class IUiAutomator(Protocol):
    @abstractmethod
    def parse_elements(self, xml_string: str) -> list[dict]:
        ...

    @abstractmethod
    def wait_for_export_completion(self, max_wait: int = 300) -> str | None:
        ...

    @abstractmethod
    def scroll_down(self, duration_ms: int = 800) -> None:
        ...

    @abstractmethod
    def scroll_up(self, duration_ms: int = 800) -> None:
        ...


class ICoordinates(Protocol):
    @abstractmethod
    def bounds_to_center(self, bounds: str) -> tuple[int, int]:
        ...


class IDolbyApp(Protocol):
    @abstractmethod
    def get_track_list(self, xml_string: str, start_index: int = 1) -> list:
        ...

    @abstractmethod
    def has_more_items_below(self, xml_string: str) -> bool:
        ...

    @abstractmethod
    def find_element(self, xml_string: str, **attrs) -> dict | None:
        ...


class IReportGenerator(Protocol):
    @abstractmethod
    def generate(self, output_path: str, **kwargs) -> None:
        ...