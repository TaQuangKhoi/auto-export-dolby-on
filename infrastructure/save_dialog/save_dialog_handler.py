from abc import ABC, abstractmethod
from typing import Protocol


class ISaveDialogHandler(Protocol):
    @abstractmethod
    def handle_save_dialog(self, adb_client, ui_automator, coords, config: dict) -> str | None:
        ...

    @abstractmethod
    def detect(self, xml_string: str) -> bool:
        ...