# ===================================================================
# TRACKPROCESSOR.PS1 - Track Export & Delete Functions
# ===================================================================
# Contains high-level functions for processing tracks

. "$PSScriptRoot\Config.ps1"
. "$PSScriptRoot\UiAutomator.ps1"
. "$PSScriptRoot\Coordinates.ps1"
. "$PSScriptRoot\DolbyAppHelper.ps1"

function Export-TrackToGoogleDrive {
    <#
    .SYNOPSIS
    Exports current track to Google Drive (from detail screen)
    
    .DESCRIPTION
    Handles the complete export flow:
    1. Click Share button
    2. Click Export Lossless
    3. Wait for export to complete
    4. Click Drive
    5. Click Save
    
    .OUTPUTS
    Boolean - $true if successful, $false otherwise
    #>
    param(
        [Parameter(Mandatory)]
        [string]$AdbPath,
        
        [Parameter(Mandatory)]
        [hashtable]$Config,
        
        [Parameter(Mandatory)]
        [string]$TrackTitle
    )
    
    Write-Host "`n  → Exporting '$TrackTitle' to Google Drive..." -ForegroundColor Cyan
    
    # Step 1: Get detail screen and find Share button
    $detailXml = Get-UiDump -AdbPath $AdbPath
    if (-not $detailXml) {
        Write-Host "  ❌ Failed to get detail screen" -ForegroundColor Red
        return $false
    }
    
    $shareButton = Find-UiElement -XmlString $detailXml -ResourceId $Config.DolbyApp.ResourceIds.ShareButton
    if (-not $shareButton) {
        Write-Host "  ❌ Share button not found" -ForegroundColor Red
        return $false
    }
    
    # Step 2: Click Share
    if (-not (Invoke-TapElement -Element $shareButton -AdbPath $AdbPath -Description "Share button")) {
        Write-Host "  ❌ Failed to click Share button" -ForegroundColor Red
        return $false
    }
    
    Start-Sleep -Seconds $Config.WaitTimes.PopupAppear
    
    # Step 3: Get share popup and find Export Lossless
    $sharePopupXml = Get-UiDump -AdbPath $AdbPath
    if (-not $sharePopupXml) {
        Write-Host "  ❌ Failed to get share popup" -ForegroundColor Red
        return $false
    }
    
    $exportButton = Find-UiElement -XmlString $sharePopupXml -ResourceId $Config.DolbyApp.ResourceIds.ExportLossless
    if (-not $exportButton) {
        Write-Host "  ❌ Export Lossless button not found" -ForegroundColor Red
        return $false
    }
    
    # Step 4: Click Export Lossless
    if (-not (Invoke-TapElement -Element $exportButton -AdbPath $AdbPath -Description "Export Lossless")) {
        Write-Host "  ❌ Failed to click Export Lossless" -ForegroundColor Red
        return $false
    }
    
    # Step 5: Wait for export to complete
    Write-Host "  ⏱️  Waiting for export to complete..." -ForegroundColor Gray
    $saveDialogXml = Wait-ForExportCompletion `
        -AdbPath $AdbPath `
        -MaxWaitSeconds $Config.WaitTimes.ExportMaxWait `
        -CheckIntervalSeconds $Config.WaitTimes.ExportCheckInterval
    
    if (-not $saveDialogXml) {
        Write-Host "  ❌ Export timed out" -ForegroundColor Red
        return $false
    }
    
    # Step 6: Find and click Drive button
    $driveButton = Find-UiElement -XmlString $saveDialogXml -Text "Drive"
    if (-not $driveButton) {
        $driveButton = Find-UiElement -XmlString $saveDialogXml -ContentDesc "Drive"
    }
    
    if (-not $driveButton) {
        Write-Host "  ⚠️  Drive button not found - may need manual save" -ForegroundColor Yellow
        return $false
    }
    
    if (-not (Invoke-TapElement -Element $driveButton -AdbPath $AdbPath -Description "Drive")) {
        Write-Host "  ❌ Failed to click Drive button" -ForegroundColor Red
        return $false
    }
    
    Start-Sleep -Seconds 3
    
    # Step 7: Get Drive screen and click Save
    $driveScreenXml = Get-UiDump -AdbPath $AdbPath
    if (-not $driveScreenXml) {
        Write-Host "  ❌ Failed to get Drive screen" -ForegroundColor Red
        return $false
    }
    
    $saveButton = Find-UiElement -XmlString $driveScreenXml -ResourceId "com.google.android.apps.docs:id/save_button"
    if (-not $saveButton) {
        $saveButton = Find-UiElement -XmlString $driveScreenXml -Text "Save"
    }
    
    if (-not $saveButton) {
        Write-Host "  ⚠️  Save button not found" -ForegroundColor Yellow
        return $false
    }
    
    if (-not (Invoke-TapElement -Element $saveButton -AdbPath $AdbPath -Description "Save")) {
        Write-Host "  ❌ Failed to click Save button" -ForegroundColor Red
        return $false
    }
    
    # Wait for save to complete and return to detail screen
    Start-Sleep -Seconds $Config.WaitTimes.ReturnToDetail
    
    Write-Host "  ✓ Export completed successfully" -ForegroundColor Green
    return $true
}

function Remove-CurrentTrack {
    <#
    .SYNOPSIS
    Deletes current track (from detail screen)
    
    .DESCRIPTION
    Handles the complete delete flow:
    1. Click More button
    2. Click Delete option
    3. Confirm deletion
    4. Wait for return to library
    
    .OUTPUTS
    Boolean - $true if successful, $false otherwise
    #>
    param(
        [Parameter(Mandatory)]
        [string]$AdbPath,
        
        [Parameter(Mandatory)]
        [hashtable]$Config,
        
        [Parameter(Mandatory)]
        [string]$TrackTitle
    )
    
    Write-Host "`n  → Deleting '$TrackTitle'..." -ForegroundColor Yellow
    
    # Step 1: Wait for detail screen to stabilize
    Start-Sleep -Seconds $Config.WaitTimes.ScreenLoad
    
    # Step 2: Get current screen and find More button
    $detailXml = Get-UiDump -AdbPath $AdbPath
    if (-not $detailXml) {
        Write-Host "  ❌ Failed to get detail screen" -ForegroundColor Red
        return $false
    }
    
    $moreButton = Find-UiElement -XmlString $detailXml -ResourceId $Config.DolbyApp.ResourceIds.MoreButton
    if (-not $moreButton) {
        Write-Host "  ❌ More button not found" -ForegroundColor Red
        return $false
    }
    
    # Step 3: Click More button
    if (-not (Invoke-TapElement -Element $moreButton -AdbPath $AdbPath -Description "More button")) {
        Write-Host "  ❌ Failed to click More button" -ForegroundColor Red
        return $false
    }
    
    Start-Sleep -Seconds $Config.WaitTimes.PopupAppear
    
    # Step 4: Get More dialog and find Delete option
    $moreDialogXml = Get-UiDump -AdbPath $AdbPath
    if (-not $moreDialogXml) {
        Write-Host "  ❌ Failed to get More dialog" -ForegroundColor Red
        return $false
    }
    
    $deleteOption = Find-UiElement -XmlString $moreDialogXml -Text "Delete"
    if (-not $deleteOption) {
        $deleteOption = Find-UiElement -XmlString $moreDialogXml -ContentDesc "Delete"
    }
    if (-not $deleteOption) {
        $deleteOption = Find-UiElement -XmlString $moreDialogXml -ResourceId $Config.DolbyApp.ResourceIds.DeleteOption
    }
    
    if (-not $deleteOption) {
        Write-Host "  ❌ Delete option not found" -ForegroundColor Red
        return $false
    }
    
    # Step 5: Click Delete option
    if (-not (Invoke-TapElement -Element $deleteOption -AdbPath $AdbPath -Description "Delete")) {
        Write-Host "  ❌ Failed to click Delete option" -ForegroundColor Red
        return $false
    }
    
    Start-Sleep -Seconds $Config.WaitTimes.DeleteConfirm
    
    # Step 6: Get confirmation dialog and find Confirm button
    $confirmXml = Get-UiDump -AdbPath $AdbPath
    if (-not $confirmXml) {
        Write-Host "  ❌ Failed to get confirmation dialog" -ForegroundColor Red
        return $false
    }
    
    $confirmButton = Find-UiElement -XmlString $confirmXml -Text "Delete"
    if (-not $confirmButton) {
        $confirmButton = Find-UiElement -XmlString $confirmXml -Text "OK"
    }
    if (-not $confirmButton) {
        $confirmButton = Find-UiElement -XmlString $confirmXml -Text "Yes"
    }
    if (-not $confirmButton) {
        $confirmButton = Find-UiElement -XmlString $confirmXml -ResourceId $Config.DolbyApp.ResourceIds.ConfirmDeleteButton
    }
    
    if (-not $confirmButton) {
        Write-Host "  ❌ Confirm button not found" -ForegroundColor Red
        return $false
    }
    
    # Step 7: Confirm deletion
    if (-not (Invoke-TapElement -Element $confirmButton -AdbPath $AdbPath -Description "Confirm Delete")) {
        Write-Host "  ❌ Failed to confirm deletion" -ForegroundColor Red
        return $false
    }
    
    # Wait for UI to update and return to library
    Start-Sleep -Seconds 2
    
    Write-Host "  ✓ Track deleted successfully" -ForegroundColor Green
    return $true
}

function Process-SingleTrack {
    <#
    .SYNOPSIS
    Process one track: Export to Google Drive then Delete
    
    .OUTPUTS
    Hashtable with Success (bool), Step (string), Error (string)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$AdbPath,
        
        [Parameter(Mandatory)]
        [hashtable]$Config,
        
        [Parameter(Mandatory)]
        [object]$Track
    )
    
    Write-Host "`n  📝 Processing: $($Track.Title)" -ForegroundColor Cyan
    
    # Step 1: Export to Google Drive
    $exportSuccess = Export-TrackToGoogleDrive `
        -AdbPath $AdbPath `
        -Config $Config `
        -TrackTitle $Track.Title
    
    if (-not $exportSuccess) {
        return @{
            Success = $false
            Step = "Export"
            Error = "Failed to export track to Google Drive"
        }
    }
    
    # Step 2: Delete track
    $deleteSuccess = Remove-CurrentTrack `
        -AdbPath $AdbPath `
        -Config $Config `
        -TrackTitle $Track.Title
    
    if (-not $deleteSuccess) {
        return @{
            Success = $false
            Step = "Delete"
            Error = "Failed to delete track"
        }
    }
    
    return @{
        Success = $true
        Step = "Complete"
        Error = $null
    }
}
