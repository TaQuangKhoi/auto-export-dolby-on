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

# ===================================================================
# STEP 6A: SMART WAIT FOR EXPORT & SAVE DIALOG
# ===================================================================

Write-Host "`n[STEP 6A] Waiting for export to complete..." -ForegroundColor Green
Write-Host "⏱️  This may take a while for large files..." -ForegroundColor Cyan

$saveDialogXml = Wait-ForExportCompletion `
    -AdbPath $adb `
    -MaxWaitSeconds $config.WaitTimes.ExportMaxWait `
    -CheckIntervalSeconds $config.WaitTimes.ExportCheckInterval

if ($null -eq $saveDialogXml) {
    Write-Host "⚠️ Save Dialog did not appear. Trying to get current UI..." -ForegroundColor Yellow
    
    # Try one more time to get current screen
    Start-Sleep -Seconds 2
    $saveDialogXml = Get-UiDump -AdbPath $adb
    
    if ($null -eq $saveDialogXml) {
        Write-Host "Failed to get save dialog UI dump. Exiting." -ForegroundColor Red
        exit 1
    }
}

# ===================================================================
# STEP 7: PROCESS SAVE DIALOG
# ===================================================================

Write-Host "`n[STEP 7] Processing Android Save Dialog..." -ForegroundColor Green

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
    $driveScreenElements = @()
    $driveScreenDumpPath = $null
} else {
    Write-Host "✓ Found Drive button" -ForegroundColor Green
    
    $clickSuccess = Invoke-TapElement -Element $driveButton -AdbPath $adb -Description "Drive"
    
    if ($clickSuccess) {
        Write-Host "✓ Clicked Drive - loading Google Drive interface..." -ForegroundColor Green
        
        # Wait for Google Drive screen to load
        Write-Host "Waiting for Google Drive screen..." -ForegroundColor Gray
        Start-Sleep -Seconds 3
        
        # ===================================================================
        # STEP 9: DUMP GOOGLE DRIVE SCREEN
        # ===================================================================
        
        Write-Host "`n[STEP 9] Dumping Google Drive Screen..." -ForegroundColor Green
        
        $driveScreenXml = Get-UiDump -AdbPath $adb
        
        if ($null -eq $driveScreenXml) {
            Write-Host "Failed to get Google Drive screen UI dump." -ForegroundColor Red
            $driveScreenElements = @()
            $driveScreenDumpPath = $null
        } else {
            # Save Drive screen dump
            if ($config.EnableDump) {
                $driveScreenDumpPath = Join-Path $dumpsFolder "drive_screen_dump_$timestamp.xml"
                Save-UiDump -XmlContent $driveScreenXml -OutputPath $driveScreenDumpPath
            }
            
            # Parse Drive screen elements
            $driveScreenElements = ConvertFrom-UiXml -XmlString $driveScreenXml
            
            Write-Host "→ Found $($driveScreenElements.Count) elements in Google Drive screen" -ForegroundColor Cyan
            
            # Display important buttons/options
            Write-Host "`nImportant elements in Google Drive screen:" -ForegroundColor Yellow
            $driveScreenElements | Where-Object { 
                $_.Text -match 'save|select|folder|my drive|recent|shared|cancel|done' -or
                $_.ContentDesc -match 'save|select|folder|my drive|recent|shared|cancel|done' -or
                $_.ResourceId -match 'save|select|folder|button|action'
            } | Select-Object -First 20 | ForEach-Object {
                $display = "  • "
                if ($_.Text) { $display += "Text: '$($_.Text)' " }
                if ($_.ContentDesc) { $display += "Desc: '$($_.ContentDesc)' " }
                if ($_.ResourceId) { $display += "ID: $($_.ResourceId)" }
                Write-Host $display -ForegroundColor Gray
            }
            
            # ===================================================================
            # STEP 10: CLICK SAVE BUTTON
            # ===================================================================
            
            Write-Host "`n[STEP 10] Looking for Save button in Google Drive..." -ForegroundColor Green
            
            # Try to find Save button by resource-id first (most reliable)
            $saveButton = Find-UiElement -XmlString $driveScreenXml -ResourceId "com.google.android.apps.docs:id/save_button"
            
            if ($null -eq $saveButton) {
                # Try alternative: find by text
                $saveButton = Find-UiElement -XmlString $driveScreenXml -Text "Save"
            }
            
            if ($null -eq $saveButton) {
                Write-Host "⚠️ Save button not found in Google Drive screen." -ForegroundColor Yellow
                Write-Host "   You may need to manually save the file." -ForegroundColor Yellow
            } else {
                Write-Host "✓ Found Save button" -ForegroundColor Green
                
                $clickSuccess = Invoke-TapElement -Element $saveButton -AdbPath $adb -Description "Save button"
                
                if ($clickSuccess) {
                    Write-Host "✓ Clicked Save - file is being saved to Google Drive..." -ForegroundColor Green
                    
                    # Wait for save to complete and return to detail screen
                    Write-Host "Waiting for save to complete and return to detail screen..." -ForegroundColor Gray
                    Start-Sleep -Seconds $config.WaitTimes.ReturnToDetail
                    
                    Write-Host "✓ Export completed! Should now be back at detail screen." -ForegroundColor Green
                } else {
                    Write-Host "Failed to click Save button" -ForegroundColor Red
                }
            }
        }
    } else {
        Write-Host "Failed to click Drive button" -ForegroundColor Red
        $driveScreenElements = @()
        $driveScreenDumpPath = $null
    }
}

# ===================================================================
# STEP 9: BACK TO DETAIL SCREEN - CLICK MORE BUTTON
# ===================================================================

Write-Host "`n[STEP 9] Waiting for return to detail screen..." -ForegroundColor Green
Start-Sleep -Seconds $config.WaitTimes.ScreenLoad

Write-Host "Dumping current screen to verify we're at detail screen..." -ForegroundColor Cyan
$currentScreenXml = Get-UiDump -AdbPath $adb

if ($null -eq $currentScreenXml) {
    Write-Host "Failed to get current screen UI dump." -ForegroundColor Red
} else {
    # Verify we're on detail screen by checking for More button
    $moreButton = Find-UiElement -XmlString $currentScreenXml -ResourceId $config.DolbyApp.ResourceIds.MoreButton
    
    if ($null -eq $moreButton) {
        Write-Host "⚠️ More button not found - may not be on detail screen yet" -ForegroundColor Yellow
        Write-Host "   Waiting a bit longer..." -ForegroundColor Gray
        Start-Sleep -Seconds 2
        
        # Try again
        $currentScreenXml = Get-UiDump -AdbPath $adb
        $moreButton = Find-UiElement -XmlString $currentScreenXml -ResourceId $config.DolbyApp.ResourceIds.MoreButton
    }
    
    if ($null -ne $moreButton) {
        Write-Host "✓ Found More button - clicking to open options menu..." -ForegroundColor Green
        
        $clickSuccess = Invoke-TapElement -Element $moreButton -AdbPath $adb -Description "More button"
        
        if ($clickSuccess) {
            # Wait for More dialog to appear
            Write-Host "Waiting for More dialog..." -ForegroundColor Gray
            Start-Sleep -Seconds $config.WaitTimes.PopupAppear
            
            # ===================================================================
            # STEP 10: DUMP MORE DIALOG
            # ===================================================================
            
            Write-Host "`n[STEP 10] Dumping More Dialog..." -ForegroundColor Green
            
            $moreDialogXml = Get-UiDump -AdbPath $adb
            
            if ($null -eq $moreDialogXml) {
                Write-Host "Failed to get More dialog UI dump." -ForegroundColor Red
            } else {
                # Save More dialog dump
                if ($config.EnableDump) {
                    $moreDialogDumpPath = Join-Path $dumpsFolder "more_dialog_dump_$timestamp.xml"
                    Save-UiDump -XmlContent $moreDialogXml -OutputPath $moreDialogDumpPath
                }
                
                # Parse More dialog elements
                $moreDialogElements = ConvertFrom-UiXml -XmlString $moreDialogXml
                
                Write-Host "→ Found $($moreDialogElements.Count) elements in More dialog" -ForegroundColor Cyan
                
                # Display all options in More dialog
                Write-Host "`nAvailable options in More dialog:" -ForegroundColor Yellow
                $moreDialogElements | Where-Object { 
                    $_.Text -or $_.ContentDesc -or $_.ResourceId -match 'delete|rename|duplicate|option|item'
                } | ForEach-Object {
                    $display = "  • "
                    if ($_.Text) { $display += "Text: '$($_.Text)' " }
                    if ($_.ContentDesc) { $display += "Desc: '$($_.ContentDesc)' " }
                    if ($_.ResourceId) { $display += "ID: $($_.ResourceId)" }
                    Write-Host $display -ForegroundColor Cyan
                }
                
                # Look for Delete option
                Write-Host "`nSearching for Delete option..." -ForegroundColor Yellow
                
                $deleteOption = Find-UiElement -XmlString $moreDialogXml -Text "Delete"
                
                if ($null -eq $deleteOption) {
                    # Try alternative searches
                    $deleteOption = Find-UiElement -XmlString $moreDialogXml -ContentDesc "Delete"
                }
                
                if ($null -eq $deleteOption) {
                    # Try by resource ID
                    $deleteOption = Find-UiElement -XmlString $moreDialogXml -ResourceId $config.DolbyApp.ResourceIds.DeleteOption
                }
                
                if ($null -eq $deleteOption) {
                    Write-Host "⚠️ Delete option not found in More dialog" -ForegroundColor Yellow
                    Write-Host "   Check the elements listed above for the correct identifier" -ForegroundColor Yellow
                } else {
                    Write-Host "✓ Found Delete option!" -ForegroundColor Green
                    Write-Host "   Text: $($deleteOption.Text)" -ForegroundColor Cyan
                    Write-Host "   Resource-ID: $($deleteOption.ResourceId)" -ForegroundColor Cyan
                    Write-Host "   Bounds: $($deleteOption.Bounds)" -ForegroundColor Cyan
                    
                    # ===================================================================
                    # STEP 10A: CLICK DELETE BUTTON
                    # ===================================================================
                    
                    Write-Host "`nClicking Delete option..." -ForegroundColor Yellow
                    
                    $clickSuccess = Invoke-TapElement -Element $deleteOption -AdbPath $adb -Description "Delete option"
                    
                    if ($clickSuccess) {
                        Write-Host "✓ Clicked Delete - waiting for confirmation dialog..." -ForegroundColor Green
                        
                        # Wait for confirmation dialog
                        Start-Sleep -Seconds $config.WaitTimes.DeleteConfirm
                        
                        # ===================================================================
                        # STEP 10B: DUMP DELETE CONFIRMATION DIALOG
                        # ===================================================================
                        
                        Write-Host "`n[STEP 10B] Dumping Delete Confirmation Dialog..." -ForegroundColor Green
                        
                        $deleteConfirmXml = Get-UiDump -AdbPath $adb
                        
                        if ($null -eq $deleteConfirmXml) {
                            Write-Host "Failed to get confirmation dialog UI dump" -ForegroundColor Red
                        } else {
                            # Save confirmation dialog dump
                            if ($config.EnableDump) {
                                $deleteConfirmDumpPath = Join-Path $dumpsFolder "delete_confirm_dump_$timestamp.xml"
                                Save-UiDump -XmlContent $deleteConfirmXml -OutputPath $deleteConfirmDumpPath
                            }
                            
                            # Parse confirmation dialog elements
                            $deleteConfirmElements = ConvertFrom-UiXml -XmlString $deleteConfirmXml
                            
                            Write-Host "→ Found $($deleteConfirmElements.Count) elements in confirmation dialog" -ForegroundColor Cyan
                            
                            # Display dialog content
                            Write-Host "`nConfirmation dialog content:" -ForegroundColor Yellow
                            $deleteConfirmElements | Where-Object { 
                                $_.Text -or $_.ContentDesc
                            } | ForEach-Object {
                                $display = "  • "
                                if ($_.Text) { $display += "Text: '$($_.Text)' " }
                                if ($_.ContentDesc) { $display += "Desc: '$($_.ContentDesc)' " }
                                if ($_.ResourceId) { $display += "ID: $($_.ResourceId)" }
                                Write-Host $display -ForegroundColor Cyan
                            }
                            
                            # Look for Confirm/Delete button
                            Write-Host "`nSearching for Confirm Delete button..." -ForegroundColor Yellow
                            
                            # Try to find by text first
                            $confirmButton = Find-UiElement -XmlString $deleteConfirmXml -Text "Delete"
                            
                            if ($null -eq $confirmButton) {
                                $confirmButton = Find-UiElement -XmlString $deleteConfirmXml -Text "OK"
                            }
                            
                            if ($null -eq $confirmButton) {
                                $confirmButton = Find-UiElement -XmlString $deleteConfirmXml -Text "Yes"
                            }
                            
                            if ($null -eq $confirmButton) {
                                # Try by resource ID
                                $confirmButton = Find-UiElement -XmlString $deleteConfirmXml -ResourceId $config.DolbyApp.ResourceIds.ConfirmDeleteButton
                            }
                            
                            if ($null -eq $confirmButton) {
                                Write-Host "⚠️ Confirm Delete button not found" -ForegroundColor Yellow
                                Write-Host "   Check the elements listed above" -ForegroundColor Yellow
                            } else {
                                Write-Host "✓ Found Confirm Delete button!" -ForegroundColor Green
                                Write-Host "   Text: $($confirmButton.Text)" -ForegroundColor Cyan
                                Write-Host "   Resource-ID: $($confirmButton.ResourceId)" -ForegroundColor Cyan
                                Write-Host "   Bounds: $($confirmButton.Bounds)" -ForegroundColor Cyan
                                
                                Write-Host "`nClicking Delete to confirm..." -ForegroundColor Yellow
                                
                                $clickSuccess = Invoke-TapElement -Element $confirmButton -AdbPath $adb -Description "Confirm Delete"
                                if ($clickSuccess) {
                                    Write-Host "✓ Track deleted successfully!" -ForegroundColor Green
                                    Write-Host "Waiting for UI to update after deletion..." -ForegroundColor Gray
                                    Start-Sleep -Seconds 2
                                } else {
                                    Write-Host "Failed to click Delete confirmation button" -ForegroundColor Red
                                }
                            }
                        }
                    } else {
                        Write-Host "Failed to click Delete option" -ForegroundColor Red
                    }
                }
            }
        } else {
            Write-Host "Failed to click More button" -ForegroundColor Red
        }
    } else {
        Write-Host "Could not find More button - unable to proceed" -ForegroundColor Red
    }
}

# ===================================================================
# STEP 11: GENERATE HTML REPORT
# ===================================================================

Write-Host "`n[STEP 11] Generating HTML Report..." -ForegroundColor Green

# Initialize variables if not set
if (-not (Test-Path variable:moreDialogElements)) {
    $moreDialogElements = @()
}

if (-not (Test-Path variable:deleteConfirmElements)) {
    $deleteConfirmElements = @()
}

if ($config.EnableReport) {
    $reportPath = Join-Path $dumpsFolder "report_$timestamp.html"
    
    New-HtmlReport `
        -OutputPath $reportPath `
        -Tracks $tracks `
        -DetailElements $detailElements `
        -SharePopupElements $sharePopupElements `
        -SaveDialogElements $saveDialogElements `
        -DriveScreenElements $driveScreenElements `
        -MoreDialogElements $moreDialogElements `
        -DeleteConfirmElements $deleteConfirmElements `
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
Write-Host "  • More dialog elements: $($moreDialogElements.Count)" -ForegroundColor White
Write-Host "  • Delete confirm elements: $($deleteConfirmElements.Count)" -ForegroundColor White
Write-Host "  • Save dialog elements: $($saveDialogElements.Count)" -ForegroundColor White
Write-Host "  • Drive screen elements: $($driveScreenElements.Count)" -ForegroundColor White

if ($config.EnableDump -or $config.EnableReport) {
    Write-Host "`n📁 Generated Files:" -ForegroundColor Yellow
    if ($config.EnableDump) {
        Write-Host "  • $libraryDumpPath" -ForegroundColor Gray
        Write-Host "  • $detailDumpPath" -ForegroundColor Gray
        if ($sharePopupDumpPath) { Write-Host "  • $sharePopupDumpPath" -ForegroundColor Gray }
        if ($saveDialogDumpPath) { Write-Host "  • $saveDialogDumpPath" -ForegroundColor Gray }
        if ($driveScreenDumpPath) { Write-Host "  • $driveScreenDumpPath" -ForegroundColor Gray }
    }
    if ($config.EnableReport) {
        Write-Host "  • $reportPath" -ForegroundColor White
        Write-Host "`n💡 Open the HTML report in your browser!" -ForegroundColor Cyan
    }
}

Write-Host ""
