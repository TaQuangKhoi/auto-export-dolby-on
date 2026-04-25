from dataclasses import dataclass
from domain.entities import Track
from domain.exceptions import AdbCommandError
from domain.interfaces import IAdbClient, IDolbyApp, IUiAutomator


@dataclass
class ListTracksResult:
    tracks: list[Track]
    total_pages: int
    has_more: bool


class ListTracksUseCase:
    def __init__(
        self,
        adb_client: IAdbClient,
        dolby_app: IDolbyApp,
        ui_automator: IUiAutomator,
        config: dict,
    ):
        self._adb = adb_client
        self._app = dolby_app
        self._ui = ui_automator
        self._config = config

    def execute(self, scroll_all: bool = False, save_xml_path: str | None = None) -> ListTracksResult:
        all_tracks = []
        seen_bounds: set[str] = set()
        page_count = 0

        while True:
            xml = self._adb.dump_ui()
            page_count += 1

            if save_xml_path and page_count == 1:
                with open(save_xml_path, "w") as f:
                    f.write(xml)

            page_tracks = self._app.get_track_list(xml, start_index=len(all_tracks) + 1)
            if not page_tracks:
                break

            new_tracks = []
            for track in page_tracks:
                if track.bounds and track.bounds in seen_bounds:
                    continue
                seen_bounds.add(track.bounds)
                new_tracks.append(track)

            if not new_tracks:
                break

            all_tracks.extend(new_tracks)

            if not scroll_all:
                break

            if not self._app.has_more_items_below(xml):
                break

            self._ui.scroll_down()
            self._sleep(self._config.get("WaitTimes", {}).get("ScreenLoad", 2))

        return ListTracksResult(
            tracks=all_tracks,
            total_pages=page_count,
            has_more=scroll_all and self._app.has_more_items_below(xml) if xml else False,
        )

    def _sleep(self, seconds: float) -> None:
        import time
        time.sleep(seconds)


class GetDeviceStatusUseCase:
    def __init__(self, adb_client: IAdbClient, config: dict):
        self._adb = adb_client
        self._config = config

    def execute(self) -> dict:
        pkg = self._adb.get_foreground_package()
        target = self._config["DolbyApp"]["Package"]
        return {
            "foreground_package": pkg,
            "dolby_app_package": target,
            "is_dolby_foreground": pkg == target,
            "adb_path": self._adb.find_adb(),
        }