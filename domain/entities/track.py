from dataclasses import dataclass


@dataclass
class Track:
    index: int
    title: str
    date: str
    duration: str
    bounds: str

    @property
    def display_name(self) -> str:
        return f"{self.index}. {self.title}"


@dataclass
class ExportResult:
    success: bool
    step: str
    error: str | None = None
    track_title: str = ""

    @property
    def is_success(self) -> bool:
        return self.success


@dataclass
class ProcessResult:
    success: bool
    processed: int
    succeeded: int
    failed: int
    failed_tracks: list[dict]