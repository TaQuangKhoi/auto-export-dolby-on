# AGENTS.md

## Project Overview
Automates exporting lossless audio from Dolby On app to Google Drive via Android ADB.

## Architecture
Two implementations coexist:
- **PowerShell**: `main_modular.ps1` + `modules/*.ps1` (primary, fully implemented)
- **Python**: Clean Architecture refactor under `domain/`, `application/`, `infrastructure/`, `presentation/` (partially implemented)

Entry points:
- PowerShell: `pwsh main_modular.ps1`
- Python: `python main.py` or `python presentation/main.py`

## Clean Architecture Layers
- `domain/entities/` — `Track`, `ExportResult`, `ProcessResult` dataclasses
- `domain/interfaces/` — repository interfaces
- `domain/exceptions/` — domain exceptions
- `application/use_cases/` — `export_track.py`, `delete_track.py`, `process_all.py`
- `infrastructure/adb/` — `AdbClient`
- `infrastructure/ui/` — UI-related infrastructure
- `infrastructure/reporting/` — reporting infrastructure

## Required Environment
- **ADB**: Must be in `PATH`, or set `ADB_PATH` env var, or have `ANDROID_HOME`/`ANDROID_SDK_ROOT` pointing to `platform-tools/`
- Run `adb shell input keyevent 3` to verify connectivity before automating

## Key Commands
```bash
# Run PowerShell automation
pwsh main_modular.ps1

# Run Python entrypoint
python main.py

# Python clean architecture entrypoint
python presentation/main.py
```

## Important Paths
- `dumps/` — UI XML dumps (gitignored, created at runtime)
- `.opencode/` — OpenCode plugin dependencies (gitignored)
- `modules/` — PowerShell modules imported by `main_modular.ps1`

## App-Specific Constants (Dolby On)
- Package: `com.dolby.dolby234`
- RecyclerView ID: `com.dolby.dolby234:id/library_items_recycler_view`
- Export option ID: `com.dolby.dolby234:id/share_option_lossless_audio_item`
- Share button ID: `com.dolby.dolby234:id/track_details_share`

## Package Manager
- Python: `uv` (lockfile: `uv.lock`)
- Node (`.opencode/`): local install only, not a workspace
