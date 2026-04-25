from rich.console import Console
from rich.table import Table
from rich import box
from domain.interfaces import ITrackPresenter


class RichTrackListPresenter:
    def __init__(self, verbose: bool = False):
        self._verbose = verbose
        self._console = Console()
        self._buffer: list[tuple] = []
        self._page_count = 0

    def present_page(self, tracks: list, page_num: int) -> None:
        self._page_count = page_num
        if not tracks:
            if self._verbose:
                self._console.print(f"[dim]  → Page {page_num}: end of list[/dim]")
            return
        for t in tracks:
            self._buffer.append((str(t.index), t.title, t.duration, t.date))
        if self._verbose:
            self._console.print(f"[dim]  → Page {page_num} done ({len(tracks)} track(s))[/dim]")

    def present_final(self, tracks: list, total_pages: int) -> None:
        table = Table(
            title="[bold]Dolby On Library[/bold]",
            box=box.ROUNDED,
            show_header=True,
            header_style="bold cyan",
            show_lines=False,
            expand=False,
        )
        table.add_column("#", justify="right", style="cyan", width=4, no_wrap=True)
        table.add_column("Title", style="bold")
        table.add_column("Duration", justify="center", style="yellow", width=10)
        table.add_column("Date", justify="left", style="green")

        for idx, title, duration, date in self._buffer:
            title = title if title != "(No Title)" else f"[dim](No Title)[/dim]"
            duration = f"({duration})" if duration else "[dim]()[/dim]"
            date = date or "[dim]—[/dim]"
            table.add_row(idx, title, duration, date)

        self._console.print(table)
        self._console.print(f"\n[bold]Total:[/bold] {len(tracks)} track(s) across {total_pages} page(s)")
