from dataclasses import dataclass
from domain.entities import Track
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

    def execute(
        self,
        scroll_all: bool = False,
        save_xml_path: str | None = None,
        save_xml_folder: str | None = None,
        on_page: callable | None = None,
    ) -> ListTracksResult:
        seen_track_ids: set[str] = set()
        all_tracks = []
        page_count = 0
        last_xml = ""

        while True:
            xml = self._adb.dump_ui()
            last_xml = xml
            page_count += 1

            if save_xml_path:
                import pathlib
                p = pathlib.Path(save_xml_path)
                if p.is_dir():
                    xml_path = p / f"page{page_count}.xml"
                else:
                    xml_path = p.parent / f"{p.stem}{page_count}{p.suffix}"
                xml_path.parent.mkdir(parents=True, exist_ok=True)
                with open(xml_path, "w") as f:
                    f.write(xml)

            if save_xml_folder:
                import pathlib
                folder = pathlib.Path(save_xml_folder)
                folder.mkdir(parents=True, exist_ok=True)
                xml_path = folder / f"page{page_count}.xml"
                with open(xml_path, "w") as f:
                    f.write(xml)

            page_tracks = self._app.get_track_list(xml, start_index=len(all_tracks) + 1, seen_track_ids=seen_track_ids)

            if on_page:
                is_last = not scroll_all or not page_tracks
                on_page(page_count, page_tracks, is_last)

            if not page_tracks:
                break

            all_tracks.extend(page_tracks)

            if not scroll_all:
                break

            self._ui.scroll_down()
            self._sleep(self._config.get("WaitTimes", {}).get("ScreenLoad", 2))

        for i, track in enumerate(all_tracks, start=1):
            track.index = i

        return ListTracksResult(
            tracks=all_tracks,
            total_pages=page_count,
            has_more=scroll_all and self._app.has_more_items_below(last_xml) if last_xml else False,
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