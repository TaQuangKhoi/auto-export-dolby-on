# ===================================================================
# REPORTGENERATOR.PS1 - HTML Report Generation
# ===================================================================
# Generates HTML reports from automation runs

function New-HtmlReport {
    <#
    .SYNOPSIS
    Generates comprehensive HTML report from automation session
    
    .PARAMETER OutputPath
    Path to save HTML report
    
    .PARAMETER Tracks
    Array of track objects from library
    
    .PARAMETER DetailElements
    UI elements from track detail screen
    
    .PARAMETER SharePopupElements
    UI elements from share popup
    
    .PARAMETER SaveDialogElements
    UI elements from Android save dialog
    
    .PARAMETER DriveScreenElements
    UI elements from Google Drive screen
    
    .PARAMETER MoreDialogElements
    UI elements from More dialog (contains Delete option)
    
    .PARAMETER DeleteConfirmElements
    UI elements from Delete confirmation dialog
    
    .PARAMETER Timestamp
    Session timestamp string
    #>
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,
        
        [array]$Tracks = @(),
        [array]$DetailElements = @(),
        [array]$SharePopupElements = @(),
        [array]$SaveDialogElements = @(),
        [array]$DriveScreenElements = @(),
        [array]$MoreDialogElements = @(),
        [array]$DeleteConfirmElements = @(),
        
        [Parameter(Mandatory)]
        [string]$Timestamp
    )
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='UTF-8'>
    <title>Dolby On Automation Report - $Timestamp</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #1976d2; border-bottom: 3px solid #1976d2; padding-bottom: 10px; }
        h2 { color: #424242; margin-top: 30px; border-left: 4px solid #1976d2; padding-left: 15px; }
        .section { margin: 20px 0; padding: 20px; background: #fafafa; border-radius: 5px; }
        .track { background: white; padding: 15px; margin: 10px 0; border-left: 4px solid #4caf50; border-radius: 4px; }
        .track-title { font-weight: bold; color: #1976d2; font-size: 16px; }
        .track-meta { color: #757575; font-size: 14px; margin-top: 5px; }
        .element { background: white; padding: 12px; margin: 8px 0; border: 1px solid #e0e0e0; border-radius: 4px; font-size: 13px; }
        .element-label { font-weight: bold; color: #1976d2; }
        .warning { background: #fff3cd; border-left: 4px solid #ff9800; padding: 15px; margin: 10px 0; }
        .success { background: #d4edda; border-left: 4px solid #4caf50; padding: 15px; margin: 10px 0; }
        code { background: #f5f5f5; padding: 2px 6px; border-radius: 3px; font-family: 'Consolas', monospace; }
        pre { background: #263238; color: #aed581; padding: 15px; border-radius: 5px; overflow-x: auto; }
        .stats { display: flex; gap: 20px; margin: 20px 0; }
        .stat-box { flex: 1; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 8px; text-align: center; }
        .stat-number { font-size: 36px; font-weight: bold; }
        .stat-label { font-size: 14px; opacity: 0.9; margin-top: 5px; }
    </style>
</head>
<body>
    <div class='container'>
        <h1>🎵 Dolby On Automation Report</h1>
        <p>Generated: $Timestamp</p>
        
        <div class='stats'>
            <div class='stat-box'>
                <div class='stat-number'>$($Tracks.Count)</div>
                <div class='stat-label'>Tracks Found</div>
            </div>
            <div class='stat-box' style='background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);'>
                <div class='stat-number'>$($DetailElements.Count)</div>
                <div class='stat-label'>Detail Screen Elements</div>
            </div>
            <div class='stat-box' style='background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);'>
                <div class='stat-number'>$($SharePopupElements.Count)</div>
                <div class='stat-label'>Share Popup Elements</div>
            </div>
        </div>
        
        <div class='section'>
            <h2>📚 Library Tracks</h2>
"@

    if ($Tracks.Count -eq 0) {
        $html += "<p class='warning'>⚠️ No tracks found in library</p>"
    } else {
        foreach ($track in $Tracks) {
            $html += @"
            <div class='track'>
                <div class='track-title'>$($track.Index). $($track.Title)</div>
                <div class='track-meta'>
                    📅 $($track.Date) | ⏱️ $($track.Duration)
                </div>
            </div>
"@
        }
    }

    $html += @"
        </div>
        
        <div class='section'>
            <h2>🔍 Track Detail Screen</h2>
            <p>Elements found after clicking first track:</p>
"@

    if ($DetailElements.Count -eq 0) {
        $html += "<p class='warning'>⚠️ No UI elements found on detail screen</p>"
    } else {
        foreach ($elem in $DetailElements) {
            if ($elem.ResourceId -match 'share|export|button|menu' -or 
                $elem.Text -match 'share|export|save|send' -or
                $elem.ContentDesc -match 'share|export|save|send') {
                
                $html += "<div class='element'>"
                if ($elem.ResourceId) { $html += "<div><span class='element-label'>ID:</span> <code>$($elem.ResourceId)</code></div>" }
                if ($elem.Text) { $html += "<div><span class='element-label'>Text:</span> $($elem.Text)</div>" }
                if ($elem.ContentDesc) { $html += "<div><span class='element-label'>Desc:</span> $($elem.ContentDesc)</div>" }
                if ($elem.Class) { $html += "<div><span class='element-label'>Class:</span> $($elem.Class)</div>" }
                $html += "</div>"
            }
        }
    }

    $html += @"
        </div>
        
        <div class='section'>
            <h2>📤 Share Popup Elements</h2>
"@

    if ($SharePopupElements.Count -eq 0) {
        $html += "<p class='warning'>⚠️ No UI elements found in share popup</p>"
    } else {
        $html += "<p class='success'>✓ Found $($SharePopupElements.Count) elements in share popup</p>"
        foreach ($elem in $SharePopupElements) {
            $html += "<div class='element'>"
            if ($elem.ResourceId) { $html += "<div><span class='element-label'>ID:</span> <code>$($elem.ResourceId)</code></div>" }
            if ($elem.Text) { $html += "<div><span class='element-label'>Text:</span> $($elem.Text)</div>" }
            if ($elem.ContentDesc) { $html += "<div><span class='element-label'>Desc:</span> $($elem.ContentDesc)</div>" }
            if ($elem.Class) { $html += "<div><span class='element-label'>Class:</span> $($elem.Class)</div>" }
            $html += "</div>"
        }
    }

    $html += @"
        </div>
        
        <div class='section'>
            <h2>💾 Android Save Dialog</h2>
"@

    if ($SaveDialogElements.Count -eq 0) {
        $html += "<p class='warning'>⚠️ No UI elements found in save dialog</p>"
    } else {
        $html += "<p class='success'>✓ Found $($SaveDialogElements.Count) elements in save dialog</p>"
        foreach ($elem in $SaveDialogElements) {
            $html += "<div class='element'>"
            if ($elem.ResourceId) { $html += "<div><span class='element-label'>ID:</span> <code>$($elem.ResourceId)</code></div>" }
            if ($elem.Text) { $html += "<div><span class='element-label'>Text:</span> $($elem.Text)</div>" }
            if ($elem.ContentDesc) { $html += "<div><span class='element-label'>Desc:</span> $($elem.ContentDesc)</div>" }
            if ($elem.Class) { $html += "<div><span class='element-label'>Class:</span> $($elem.Class)</div>" }
            $html += "</div>"
        }
    }

    $html += @"
        </div>
        
        <div class='section'>
            <h2>☁️ Google Drive Screen</h2>
"@

    if ($DriveScreenElements.Count -eq 0) {
        $html += "<p class='warning'>⚠️ No UI elements found in Google Drive screen (may not have been reached)</p>"
    } else {
        $html += "<p class='success'>✓ Found $($DriveScreenElements.Count) elements in Google Drive screen</p>"
        foreach ($elem in $DriveScreenElements) {
            if ($elem.Text -match 'save|select|folder|drive|recent|shared|cancel|done' -or
                $elem.ContentDesc -match 'save|select|folder|drive|recent|shared|cancel|done' -or
                $elem.ResourceId -match 'save|select|folder|button|action|title') {
                
                $html += "<div class='element'>"
                if ($elem.ResourceId) { $html += "<div><span class='element-label'>ID:</span> <code>$($elem.ResourceId)</code></div>" }
                if ($elem.Text) { $html += "<div><span class='element-label'>Text:</span> $($elem.Text)</div>" }
                if ($elem.ContentDesc) { $html += "<div><span class='element-label'>Desc:</span> $($elem.ContentDesc)</div>" }
                if ($elem.Class) { $html += "<div><span class='element-label'>Class:</span> $($elem.Class)</div>" }
                $html += "</div>"
            }
        }
    }

    $html += @"
        </div>
        
        <div class='section'>
            <h2>⚙️ More Dialog (Delete Option)</h2>
"@

    if ($MoreDialogElements.Count -eq 0) {
        $html += "<p class='warning'>⚠️ No UI elements found in More dialog (may not have been reached)</p>"
    } else {
        $html += "<p class='success'>✓ Found $($MoreDialogElements.Count) elements in More dialog</p>"
        foreach ($elem in $MoreDialogElements) {
            if ($elem.Text -match 'delete|rename|duplicate|cancel|option' -or
                $elem.ContentDesc -match 'delete|rename|duplicate|cancel|option' -or
                $elem.ResourceId -match 'delete|rename|duplicate|option|item') {
                
                $html += "<div class='element'>"
                if ($elem.ResourceId) { $html += "<div><span class='element-label'>ID:</span> <code>$($elem.ResourceId)</code></div>" }
                if ($elem.Text) { $html += "<div><span class='element-label'>Text:</span> $($elem.Text)</div>" }
                if ($elem.ContentDesc) { $html += "<div><span class='element-label'>Desc:</span> $($elem.ContentDesc)</div>" }
                if ($elem.Class) { $html += "<div><span class='element-label'>Class:</span> $($elem.Class)</div>" }
                $html += "</div>"
            }
        }
    }

    $html += @"
        </div>
        
        <div class='section'>
            <h2>🗑️ Delete Confirmation Dialog</h2>
"@

    if ($DeleteConfirmElements.Count -eq 0) {
        $html += "<p class='warning'>⚠️ No UI elements found in Delete confirmation dialog (may not have been reached)</p>"
    } else {
        $html += "<p class='success'>✓ Found $($DeleteConfirmElements.Count) elements in Delete confirmation dialog</p>"
        foreach ($elem in $DeleteConfirmElements) {
            $html += "<div class='element'>"
            if ($elem.ResourceId) { $html += "<div><span class='element-label'>ID:</span> <code>$($elem.ResourceId)</code></div>" }
            if ($elem.Text) { $html += "<div><span class='element-label'>Text:</span> $($elem.Text)</div>" }
            if ($elem.ContentDesc) { $html += "<div><span class='element-label'>Desc:</span> $($elem.ContentDesc)</div>" }
            if ($elem.Class) { $html += "<div><span class='element-label'>Class:</span> $($elem.Class)</div>" }
            $html += "</div>"
        }
    }

    $html += @"
        </div>
    </div>
</body>
</html>
"@
    
    try {
        $html | Set-Content -Path $OutputPath -Encoding UTF8
        Write-Host "✓ HTML report saved: $OutputPath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Error saving report: $_" -ForegroundColor Red
        return $false
    }
}
