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

Write-Host "→ Total tracks found: $($tracks.Count)" -ForegroundColor Cyan

# ===================================================================
# STEP 2: CLICK FIRST TRACK
# ===================================================================

Write-Host "`n[STEP 2] Clicking First Track..." -ForegroundColor Green

$firstTrack = $tracks[0]
Write-Host "→ Track: $($firstTrack.Title)" -ForegroundColor Cyan

$clickSuccess = Invoke-TapElement -Element $firstTrack -AdbPath $adb -Description "track '$($firstTrack.Title)'"

if (-not $clickSuccess) {
    Write-Host "Failed to click first track. Exiting." -ForegroundColor Red
    exit 1
}

# Wait for detail screen to load
Write-Host "Waiting for detail screen..." -ForegroundColor Gray
Start-Sleep -Seconds $config.WaitTimes.ScreenLoad

# ===================================================================
# STEP 3: DUMP DETAIL SCREEN
# ===================================================================

Write-Host "`n[STEP 3] Dumping Track Detail Screen..." -ForegroundColor Green

$detailXml = Get-UiDump -AdbPath $adb

if ($null -eq $detailXml) {
    Write-Host "Failed to get detail screen UI dump." -ForegroundColor Red
    exit 1
}

# Save detail dump
if ($config.EnableDump) {
    $detailDumpPath = Join-Path $dumpsFolder "detail_dump_$timestamp.xml"
    Save-UiDump -XmlContent $detailXml -OutputPath $detailDumpPath
}

# Parse detail screen elements
$detailElements = ConvertFrom-UiXml -XmlString $detailXml

# ===================================================================
# STEP 4: CLICK SHARE BUTTON
# ===================================================================

Write-Host "`n[STEP 4] Clicking Share Button..." -ForegroundColor Green

$shareButton = Find-UiElement -XmlString $detailXml -ResourceId $config.DolbyApp.ResourceIds.ShareButton

if ($null -eq $shareButton) {
    Write-Host "Share button not found! Resource ID: $($config.DolbyApp.ResourceIds.ShareButton)" -ForegroundColor Red
    exit 1
}

$clickSuccess = Invoke-TapElement -Element $shareButton -AdbPath $adb -Description "Share button"

if (-not $clickSuccess) {
    Write-Host "Failed to click Share button. Exiting." -ForegroundColor Red
    exit 1
}

# Wait for share popup to appear
Write-Host "Waiting for share popup..." -ForegroundColor Gray
Start-Sleep -Seconds $config.WaitTimes.PopupAppear

# ===================================================================
# STEP 5: DUMP SHARE POPUP
# ===================================================================

Write-Host "`n[STEP 5] Dumping Share Popup..." -ForegroundColor Green

$sharePopupXml = Get-UiDump -AdbPath $adb

if ($null -eq $sharePopupXml) {
    Write-Host "Failed to get share popup UI dump." -ForegroundColor Red
    exit 1
}

# Save share popup dump
if ($config.EnableDump) {
    $sharePopupDumpPath = Join-Path $dumpsFolder "share_popup_dump_$timestamp.xml"
    Save-UiDump -XmlContent $sharePopupXml -OutputPath $sharePopupDumpPath
}

# Parse share popup elements
$sharePopupElements = ConvertFrom-UiXml -XmlString $sharePopupXml

# ===================================================================
# STEP 6: CLICK EXPORT LOSSLESS
# ===================================================================

Write-Host "`n[STEP 6] Clicking Export Lossless..." -ForegroundColor Green

$exportLosslessButton = Find-UiElement -XmlString $sharePopupXml -ResourceId $config.DolbyApp.ResourceIds.ExportLossless

if ($null -eq $exportLosslessButton) {
    Write-Host "Export Lossless button not found! Resource ID: $($config.DolbyApp.ResourceIds.ExportLossless)" -ForegroundColor Red
    Write-Host "Available elements in share popup:" -ForegroundColor Yellow
    $sharePopupElements | Where-Object { $_.ResourceId } | ForEach-Object {
        Write-Host "  - $($_.ResourceId)" -ForegroundColor Gray
    }
    exit 1
}

$clickSuccess = Invoke-TapElement -Element $exportLosslessButton -AdbPath $adb -Description "Export Lossless"

if (-not $clickSuccess) {
    Write-Host "Failed to click Export Lossless. Exiting." -ForegroundColor Red
    exit 1
}

# Wait for Android save dialog to appear
Write-Host "Waiting for Android save dialog..." -ForegroundColor Gray
Start-Sleep -Seconds $config.WaitTimes.SaveDialog

# ===================================================================
# STEP 7: DUMP SAVE DIALOG
# ===================================================================

Write-Host "`n[STEP 7] Dumping Android Save Dialog..." -ForegroundColor Green

$saveDialogXml = Get-UiDump -AdbPath $adb

if ($null -eq $saveDialogXml) {
    Write-Host "Failed to get save dialog UI dump." -ForegroundColor Red
    exit 1
}

# Save dialog dump
if ($config.EnableDump) {
    $saveDialogDumpPath = Join-Path $dumpsFolder "save_dialog_dump_$timestamp.xml"
    Save-UiDump -XmlContent $saveDialogXml -OutputPath $saveDialogDumpPath
}

# Parse save dialog elements
$saveDialogElements = ConvertFrom-UiXml -XmlString $saveDialogXml

Write-Host "→ Found $($saveDialogElements.Count) elements in save dialog" -ForegroundColor Cyan

# Display important buttons/options
Write-Host "`nAvailable options in save dialog:" -ForegroundColor Yellow
$saveDialogElements | Where-Object { 
    $_.Text -or $_.ContentDesc -match 'drive|save|download|folder'
} | ForEach-Object {
    if ($_.Text) { Write-Host "  - Text: $($_.Text)" -ForegroundColor Gray }
    if ($_.ContentDesc) { Write-Host "  - Desc: $($_.ContentDesc)" -ForegroundColor Gray }
}

# ===================================================================
# STEP 8: CLICK DRIVE (Google Drive)
# ===================================================================
# NOTE: This step happens AFTER Export Lossless opens the save dialog
# Look for "Drive" button/option to select Google Drive as destination

Write-Host "`n[STEP 8] Looking for Drive option..." -ForegroundColor Green

# Try to find Drive button by text or content-desc
$driveButton = Find-UiElement -XmlString $saveDialogXml -Text "Drive"

if ($null -eq $driveButton) {
    # Try alternative texts
    $driveButton = Find-UiElement -XmlString $saveDialogXml -ContentDesc "Drive"
}

if ($null -eq $driveButton) {
    Write-Host "⚠️ Drive button not found in save dialog." -ForegroundColor Yellow
    Write-Host "   You may need to manually select Drive or check available options above." -ForegroundColor Yellow
    Write-Host "   Available text elements:" -ForegroundColor Yellow
    $saveDialogElements | Where-Object { $_.Text } | ForEach-Object {
        Write-Host "     - $($_.Text)" -ForegroundColor Gray
    }
} else {
    Write-Host "✓ Found Drive button" -ForegroundColor Green
    
    $clickSuccess = Invoke-TapElement -Element $driveButton -AdbPath $adb -Description "Drive"
    
    if ($clickSuccess) {
        Write-Host "✓ Clicked Drive - file should now save to Google Drive" -ForegroundColor Green
        
        # Wait a moment for Drive to process
        Start-Sleep -Seconds 2
    } else {
        Write-Host "Failed to click Drive button" -ForegroundColor Red
    }
}

# ===================================================================
# STEP 9: GENERATE HTML REPORT
# ===================================================================

Write-Host "`n[STEP 9] Generating HTML Report..." -ForegroundColor Green

if ($config.EnableReport) {
    $reportPath = Join-Path $dumpsFolder "report_$timestamp.html"
    
    New-HtmlReport `
        -OutputPath $reportPath `
        -Tracks $tracks `
        -DetailElements $detailElements `
        -SharePopupElements $sharePopupElements `
        -SaveDialogElements $saveDialogElements `
        -Timestamp $timestamp
}

# ===================================================================
# SUMMARY
# ===================================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  ✓ AUTOMATION COMPLETE" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "📊 Summary:" -ForegroundColor Yellow
Write-Host "  • Tracks found: $($tracks.Count)" -ForegroundColor White
Write-Host "  • Detail elements: $($detailElements.Count)" -ForegroundColor White
Write-Host "  • Share popup elements: $($sharePopupElements.Count)" -ForegroundColor White
Write-Host "  • Save dialog elements: $($saveDialogElements.Count)" -ForegroundColor White

if ($config.EnableDump -or $config.EnableReport) {
    Write-Host "`n📁 Generated Files:" -ForegroundColor Yellow
    if ($config.EnableDump) {
        Write-Host "  • $libraryDumpPath" -ForegroundColor Gray
        Write-Host "  • $detailDumpPath" -ForegroundColor Gray
        if ($sharePopupDumpPath) { Write-Host "  • $sharePopupDumpPath" -ForegroundColor Gray }
        if ($saveDialogDumpPath) { Write-Host "  • $saveDialogDumpPath" -ForegroundColor Gray }
    }
    if ($config.EnableReport) {
        Write-Host "  • $reportPath" -ForegroundColor White
        Write-Host "`n💡 Open the HTML report in your browser!" -ForegroundColor Cyan
    }
}

Write-Host ""
