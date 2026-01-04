# ===================================================================
# MAIN.PS1 - Dolby On Export Automation (Modular Version)
# ===================================================================
# 
# PURPOSE:
# Automates exporting lossless audio from Dolby On app to Google Drive
#
# WORKFLOW:
# 1. Dump Library Screen → Extract list of tracks from RecyclerView
# 2. Click First Track → Navigate to track detail screen
# 3. Dump Detail Screen → Find Share button
# 4. Click Share Button → Open share popup menu
# 5. Dump Share Popup → Find "Export Lossless" option
# 6. Click Export Lossless → Trigger Android save dialog
# 7. Dump Save Dialog → Find Drive option
# 8. Click Drive → Select Google Drive as destination
# 9. Save to Drive → Complete export process
# 10. Generate Report → Create HTML summary of session
#
# NOTE: Steps 6→7→8 must happen in sequence:
#       Export Lossless opens Save Dialog, then click Drive button
# ===================================================================

# Import all modules
. "$PSScriptRoot\modules\Config.ps1"
. "$PSScriptRoot\modules\AdbHelper.ps1"
. "$PSScriptRoot\modules\UiAutomator.ps1"
. "$PSScriptRoot\modules\Coordinates.ps1"
. "$PSScriptRoot\modules\DolbyAppHelper.ps1"
. "$PSScriptRoot\modules\ReportGenerator.ps1"
. "$PSScriptRoot\modules\TrackProcessor.ps1"

# ===================================================================
# INITIALIZATION
# ===================================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  DOLBY ON EXPORT AUTOMATION" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Get configuration
$config = Get-Config

# Initialize ADB
try {
    $adb = Initialize-Adb
}
catch {
    Write-Host "Cannot proceed without ADB. Exiting." -ForegroundColor Red
    exit 1
}

# Setup output folder
$dumpsFolder = Join-Path $PSScriptRoot $config.DumpsFolder
New-Item -ItemType Directory -Path $dumpsFolder -Force | Out-Null

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

# Wait for app to stabilize
Write-Host "Waiting for app to stabilize..." -ForegroundColor Gray
Start-Sleep -Seconds $config.WaitTimes.AppStabilize

# ===================================================================
# STEP 1: DUMP LIBRARY SCREEN & EXTRACT TRACKS
# ===================================================================

Write-Host "`n[STEP 1] Dumping Library Screen..." -ForegroundColor Green

$libraryXml = Get-UiDump -AdbPath $adb

if ($null -eq $libraryXml) {
    Write-Host "Failed to get library screen UI dump. Exiting." -ForegroundColor Red
    exit 1
}

# Save library dump
if ($config.EnableDump) {
    $libraryDumpPath = Join-Path $dumpsFolder "library_dump_$timestamp.xml"
    Save-UiDump -XmlContent $libraryXml -OutputPath $libraryDumpPath
}

# Parse tracks from RecyclerView
$tracks = Get-TrackList -XmlString $libraryXml

if ($tracks.Count -eq 0) {
    Write-Host "No tracks found in library. Exiting." -ForegroundColor Red
    exit 1
}

$totalTracksInitial = $tracks.Count
Write-Host "→ Total tracks found: $totalTracksInitial" -ForegroundColor Cyan
Write-Host "`n🔄 Starting batch export for all $totalTracksInitial tracks..." -ForegroundColor Magenta

# ===================================================================
# MAIN LOOP: EXPORT ALL TRACKS
# ===================================================================

$processedCount = 0
$successCount = 0
$failedCount = 0
$failedTracks = @()

while ($tracks.Count -gt 0) {
    $processedCount++
    $currentTrack = $tracks[0]
    
    Write-Host "`n╔════════════════════════════════════════════════════════════" -ForegroundColor Magenta
    Write-Host "║ 🎵 TRACK $processedCount of $totalTracksInitial" -ForegroundColor Magenta
    Write-Host "║ Title: $($currentTrack.Title)" -ForegroundColor Magenta
    Write-Host "║ Duration: $($currentTrack.Duration)" -ForegroundColor Magenta
    Write-Host "╚════════════════════════════════════════════════════════════" -ForegroundColor Magenta
    
    # Click track to open detail screen
    Write-Host "  → Opening track detail..." -ForegroundColor Cyan
    $clickSuccess = Invoke-TapElement -Element $currentTrack -AdbPath $adb -Description "track"
    
    if (-not $clickSuccess) {
        Write-Host "  ❌ Failed to click track - skipping" -ForegroundColor Red
        $failedCount++
        $failedTracks += @{
            Title = $currentTrack.Title
            Reason = "Failed to click track"
        }
        
        # Re-scan library and continue
        Start-Sleep -Seconds 2
        $libraryXml = Get-UiDump -AdbPath $adb
        if ($libraryXml) {
            $tracks = Get-TrackList -XmlString $libraryXml
        }
        continue
    }
    
    # Wait for detail screen to load
    Start-Sleep -Seconds $config.WaitTimes.ScreenLoad
    
    # Process track (Export + Delete)
    $result = Process-SingleTrack -AdbPath $adb -Config $config -Track $currentTrack
    
    if ($result.Success) {
        $successCount++
        Write-Host "`n  ✅ Track $processedCount completed successfully!" -ForegroundColor Green
    } else {
        $failedCount++
        $failedTracks += @{
            Title = $currentTrack.Title
            Reason = "$($result.Step): $($result.Error)"
        }
        Write-Host "`n  ❌ Track $processedCount failed at step: $($result.Step)" -ForegroundColor Red
        Write-Host "     Error: $($result.Error)" -ForegroundColor Red
    }
    
    # Re-scan library to get updated track list
    Write-Host "`n  🔍 Scanning library for remaining tracks..." -ForegroundColor Gray
    Start-Sleep -Seconds 2
    
    $libraryXml = Get-UiDump -AdbPath $adb
    if (-not $libraryXml) {
        Write-Host "  ⚠️  Failed to get library screen - retrying..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        $libraryXml = Get-UiDump -AdbPath $adb
    }
    
    if ($libraryXml) {
        $tracks = Get-TrackList -XmlString $libraryXml
        Write-Host "  → Remaining tracks: $($tracks.Count)" -ForegroundColor Cyan
    } else {
        Write-Host "  ❌ Cannot continue - failed to scan library" -ForegroundColor Red
        break
    }
    
    # Progress update
    Write-Host "`n📊 Progress: $successCount succeeded, $failedCount failed, $($tracks.Count) remaining" -ForegroundColor Yellow
}

Write-Host "`n╔════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "║ ✅ BATCH EXPORT COMPLETE!" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════" -ForegroundColor Green

Write-Host "`n╔════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "║ ✅ BATCH EXPORT COMPLETE!" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════" -ForegroundColor Green

# ===================================================================
# FINAL SUMMARY
# ===================================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  📊 FINAL SUMMARY" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Total tracks processed: $processedCount" -ForegroundColor White
Write-Host "✅ Successful exports: $successCount" -ForegroundColor Green
Write-Host "❌ Failed exports: $failedCount" -ForegroundColor Red
Write-Host "📝 Remaining in library: $($tracks.Count)" -ForegroundColor Yellow

if ($failedTracks.Count -gt 0) {
    Write-Host "`n⚠️  Failed Tracks:" -ForegroundColor Yellow
    foreach ($failed in $failedTracks) {
        Write-Host "  • $($failed.Title)" -ForegroundColor Red
        Write-Host "    Reason: $($failed.Reason)" -ForegroundColor Gray
    }
}

Write-Host ""

