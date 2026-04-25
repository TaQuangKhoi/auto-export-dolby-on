from pathlib import Path


class ReportGenerator:
    def __init__(self, config: dict):
        self._config = config

    def generate(self, output_path: str, **kwargs) -> None:
        tracks = kwargs.get("tracks", [])
        timestamp = kwargs.get("timestamp", "")
        detail_elements = kwargs.get("detail_elements", [])
        share_popup_elements = kwargs.get("share_popup_elements", [])
        save_dialog_elements = kwargs.get("save_dialog_elements", [])
        drive_screen_elements = kwargs.get("drive_screen_elements", [])
        more_dialog_elements = kwargs.get("more_dialog_elements", [])
        delete_confirm_elements = kwargs.get("delete_confirm_elements", [])

        html = self._build_html(
            tracks, timestamp, detail_elements, share_popup_elements,
            save_dialog_elements, drive_screen_elements,
            more_dialog_elements, delete_confirm_elements,
        )

        Path(output_path).parent.mkdir(parents=True, exist_ok=True)
        Path(output_path).write_text(html, encoding="utf-8")

    def _build_html(self, tracks, timestamp, detail, share, save, drive, more, delete) -> str:
        return f"""<!DOCTYPE html>
<html>
<head>
    <meta charset='UTF-8'>
    <title>Dolby On Automation Report - {timestamp}</title>
    <style>
        body {{ font-family: 'Segoe UI', Arial, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }}
        .container {{ max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
        h1 {{ color: #1976d2; border-bottom: 3px solid #1976d2; padding-bottom: 10px; }}
        h2 {{ color: #424242; margin-top: 30px; border-left: 4px solid #1976d2; padding-left: 15px; }}
        .section {{ margin: 20px 0; padding: 20px; background: #fafafa; border-radius: 5px; }}
        .track {{ background: white; padding: 15px; margin: 10px 0; border-left: 4px solid #4caf50; border-radius: 4px; }}
        .track-title {{ font-weight: bold; color: #1976d2; font-size: 16px; }}
        .track-meta {{ color: #757575; font-size: 14px; margin-top: 5px; }}
        .element {{ background: white; padding: 12px; margin: 8px 0; border: 1px solid #e0e0e0; border-radius: 4px; font-size: 13px; }}
        .element-label {{ font-weight: bold; color: #1976d2; }}
        .warning {{ background: #fff3cd; border-left: 4px solid #ff9800; padding: 15px; margin: 10px 0; }}
        .success {{ background: #d4edda; border-left: 4px solid #4caf50; padding: 15px; margin: 10px 0; }}
        code {{ background: #f5f5f5; padding: 2px 6px; border-radius: 3px; font-family: 'Consolas', monospace; }}
        pre {{ background: #263238; color: #aed581; padding: 15px; border-radius: 5px; overflow-x: auto; }}
        .stats {{ display: flex; gap: 20px; margin: 20px 0; }}
        .stat-box {{ flex: 1; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 8px; text-align: center; }}
        .stat-number {{ font-size: 36px; font-weight: bold; }}
        .stat-label {{ font-size: 14px; opacity: 0.9; margin-top: 5px; }}
    </style>
</head>
<body>
    <div class='container'>
        <h1>Dolby On Automation Report</h1>
        <p>Generated: {timestamp}</p>

        <div class='stats'>
            <div class='stat-box'>
                <div class='stat-number'>{len(tracks)}</div>
                <div class='stat-label'>Tracks Found</div>
            </div>
            <div class='stat-box' style='background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);'>
                <div class='stat-number'>{len(detail)}</div>
                <div class='stat-label'>Detail Screen Elements</div>
            </div>
            <div class='stat-box' style='background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);'>
                <div class='stat-number'>{len(share)}</div>
                <div class='stat-label'>Share Popup Elements</div>
            </div>
        </div>

        <div class='section'>
            <h2>Library Tracks</h2>
            {self._render_tracks(tracks)}
        </div>

        <div class='section'>
            <h2>Track Detail Screen</h2>
            {self._render_elements(detail, filter_keywords=['share', 'export', 'button', 'menu'])}
        </div>

        <div class='section'>
            <h2>Share Popup Elements</h2>
            {self._render_elements(share)}
        </div>

        <div class='section'>
            <h2>Android Save Dialog</h2>
            {self._render_elements(save)}
        </div>

        <div class='section'>
            <h2>Google Drive Screen</h2>
            {self._render_elements(drive, filter_keywords=['save', 'select', 'folder', 'drive'])}
        </div>

        <div class='section'>
            <h2>More Dialog</h2>
            {self._render_elements(more, filter_keywords=['delete', 'rename'])}
        </div>

        <div class='section'>
            <h2>Delete Confirmation Dialog</h2>
            {self._render_elements(delete)}
        </div>
    </div>
</body>
</html>"""

    def _render_tracks(self, tracks: list) -> str:
        if not tracks:
            return "<p class='warning'>No tracks found in library</p>"
        return "\n".join(
            f"<div class='track'>"
            f"<div class='track-title'>{t.index}. {t.title}</div>"
            f"<div class='track-meta'>{t.date} | {t.duration}</div>"
            f"</div>"
            for t in tracks
        )

    def _render_elements(self, elements: list, filter_keywords: list = None) -> str:
        if not elements:
            return "<p class='warning'>No UI elements found</p>"
        lines = []
        for e in elements:
            if filter_keywords:
                text = e.get("text", "")
                rid = e.get("resource_id", "")
                cd = e.get("content_desc", "")
                if not any(kw in text.lower() or kw in rid.lower() or kw in cd.lower() for kw in filter_keywords):
                    continue
            lines.append("<div class='element'>")
            if e.get("resource_id"):
                lines.append(f"<div><span class='element-label'>ID:</span> <code>{e['resource_id']}</code></div>")
            if e.get("text"):
                lines.append(f"<div><span class='element-label'>Text:</span> {e['text']}</div>")
            if e.get("content_desc"):
                lines.append(f"<div><span class='element-label'>Desc:</span> {e['content_desc']}</div>")
            if e.get("class"):
                lines.append(f"<div><span class='element-label'>Class:</span> {e['class']}</div>")
            lines.append("</div>")
        return "\n".join(lines) if lines else "<p class='warning'>No matching elements</p>"