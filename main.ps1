# Try to locate adb automatically. If not found, print an actionable error.
function Find-Adb {
    # 1) Use PATH
    $adb = Get-Command adb -ErrorAction SilentlyContinue
    if ($adb) {
        return $adb.Source
    }

    # 2) Use explicit environment variable ADB_PATH
    $adbPath = $env:ADB_PATH
    if ($adbPath -and (Test-Path $adbPath)) {
        return $adbPath
    }

    # 3) Try ANDROID_HOME / ANDROID_SDK_ROOT/platform-tools
    $androidHome = $env:ANDROID_HOME
    if (-not $androidHome) {
        $androidHome = $env:ANDROID_SDK_ROOT
    }

    if ($androidHome) {
        $candidate = Join-Path $androidHome "platform-tools\adb.exe"
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

$ADB = Find-Adb

if (-not $ADB) {
    Write-Host "Error: 'adb' executable not found."
    Write-Host "Install Android Platform-tools and add 'adb' to your PATH, or set the environment variable ADB_PATH to the full adb path,"
    Write-Host "or set ANDROID_HOME / ANDROID_SDK_ROOT where platform-tools/adb is located."
    exit 1
}

function Invoke-Adb {
    param(
        [string]$Command
    )

    $fullCommand = "$ADB $Command"

    try {
        # Execute the command
        Invoke-Expression $fullCommand
        if ($LASTEXITCODE -ne 0) {
            Write-Host "adb command failed (exit $LASTEXITCODE): $fullCommand"
            throw "Command failed"
        }
    }
    catch {
        Write-Host "Error executing: $fullCommand"
        throw
    }
}

# Dump UI hierarchy to console and return XML string
function Get-UiDump {
    Write-Host "Dumping UI hierarchy..."
    
    try {
        # Use exec-out to dump directly to console (no file needed)
        $xmlOutput = & $ADB exec-out uiautomator dump /dev/tty 2>&1
        
        # Convert to string if array
        $fullOutput = $xmlOutput -join "`n"
        
        # Extract only the XML portion (from <?xml or <hierarchy to </hierarchy>)
        # This filters out Java stack traces and other error messages
        if ($fullOutput -match '(<\?xml.*?<hierarchy.*?</hierarchy>)') {
            $xmlString = $matches[1]
        }
        elseif ($fullOutput -match '(<hierarchy.*?</hierarchy>)') {
            $xmlString = $matches[1]
        }
        else {
            Write-Host "Warning: No valid XML hierarchy found in output"
            Write-Host "Raw output preview: $($fullOutput.Substring(0, [Math]::Min(500, $fullOutput.Length)))..."
            return $null
        }
        
        if ([string]::IsNullOrWhiteSpace($xmlString)) {
            Write-Host "Warning: No XML content received from UI dump"
            return $null
        }
        
        return $xmlString
    }
    catch {
        Write-Host "Error dumping UI: $_"
        return $null
    }
}

# Parse XML and extract UI elements with text/content-desc/resource-id/bounds
function Parse-UiElements {
    param(
        [string]$XmlString
    )
    
    if ([string]::IsNullOrWhiteSpace($XmlString)) {
        Write-Host "No XML to parse"
        return @()
    }
    
    try {
        [xml]$xmlDoc = $XmlString
        $elements = @()
        
        # Recursively traverse all nodes
        function Process-Node {
            param($node)
            
            if ($node.NodeType -eq 'Element') {
                # Extract useful attributes
                $text = $node.GetAttribute('text')
                $contentDesc = $node.GetAttribute('content-desc')
                $resourceId = $node.GetAttribute('resource-id')
                $bounds = $node.GetAttribute('bounds')
                $className = $node.GetAttribute('class')
                
                # Only add if has meaningful content
                if (![string]::IsNullOrWhiteSpace($text) -or 
                    ![string]::IsNullOrWhiteSpace($contentDesc) -or 
                    ![string]::IsNullOrWhiteSpace($resourceId)) {
                    
                    $elements += [PSCustomObject]@{
                        Class = $className
                        Text = $text
                        ContentDesc = $contentDesc
                        ResourceId = $resourceId
                        Bounds = $bounds
                    }
                }
                
                # Process child nodes
                foreach ($child in $node.ChildNodes) {
                    Process-Node $child
                }
            }
        }
        
        # Start processing from root
        Process-Node $xmlDoc.DocumentElement
        
        return $elements
    }
    catch {
        Write-Host "Error parsing XML: $_"
        return @()
    }
}

# Get all UI text from screen
function Get-ScreenText {
    Write-Host "`n=== Extracting UI Text ===" -ForegroundColor Cyan
    
    $xmlDump = Get-UiDump
    
    if ($null -eq $xmlDump) {
        Write-Host "Failed to get UI dump" -ForegroundColor Red
        return
    }
    
    $elements = Parse-UiElements -XmlString $xmlDump
    
    if ($elements.Count -eq 0) {
        Write-Host "No UI elements found" -ForegroundColor Yellow
        Write-Host "Note: If this is a game/canvas/OpenGL app, you may need OCR instead" -ForegroundColor Yellow
        return
    }
    
    Write-Host "`nFound $($elements.Count) UI elements with content:`n" -ForegroundColor Green
    
    foreach ($elem in $elements) {
        Write-Host "---"
        if (![string]::IsNullOrWhiteSpace($elem.Class)) {
            Write-Host "  Class: $($elem.Class)"
        }
        if (![string]::IsNullOrWhiteSpace($elem.Text)) {
            Write-Host "  Text: $($elem.Text)" -ForegroundColor Yellow
        }
        if (![string]::IsNullOrWhiteSpace($elem.ContentDesc)) {
            Write-Host "  Content-Desc: $($elem.ContentDesc)" -ForegroundColor Cyan
        }
        if (![string]::IsNullOrWhiteSpace($elem.ResourceId)) {
            Write-Host "  Resource-ID: $($elem.ResourceId)" -ForegroundColor Magenta
        }
        if (![string]::IsNullOrWhiteSpace($elem.Bounds)) {
            Write-Host "  Bounds: $($elem.Bounds)" -ForegroundColor Gray
        }
    }
    
    return $elements
}

# Parse bounds string [x1,y1][x2,y2] and return center coordinates
function Get-BoundsCenter {
    param(
        [string]$BoundsString
    )
    
    if ($BoundsString -match '\[(\d+),(\d+)\]\[(\d+),(\d+)\]') {
        $x1 = [int]$matches[1]
        $y1 = [int]$matches[2]
        $x2 = [int]$matches[3]
        $y2 = [int]$matches[4]
        
        $centerX = [int](($x1 + $x2) / 2)
        $centerY = [int](($y1 + $y2) / 2)
        
        return @{
            X = $centerX
            Y = $centerY
        }
    }
    
    return $null
}

# Find all items in RecyclerView (specifically for Dolby app library)
function Get-RecyclerViewItems {
    param(
        [string]$XmlString
    )
    
    Write-Host "`n=== Finding RecyclerView Items ===" -ForegroundColor Cyan
    
    if ([string]::IsNullOrWhiteSpace($XmlString)) {
        Write-Host "No XML to parse" -ForegroundColor Red
        return @()
    }
    
    try {
        [xml]$xmlDoc = $XmlString
        $items = @()
        
        # Find the RecyclerView node
        $recyclerView = $xmlDoc.SelectSingleNode("//node[@resource-id='com.dolby.dolby234:id/library_items_recycler_view']")
        
        if ($null -eq $recyclerView) {
            Write-Host "RecyclerView not found" -ForegroundColor Yellow
            return @()
        }
        
        # Find all swipe_layout items (these are the track items)
        $trackNodes = $recyclerView.SelectNodes(".//node[@resource-id='com.dolby.dolby234:id/swipe_layout']")
        
        if ($null -eq $trackNodes -or $trackNodes.Count -eq 0) {
            Write-Host "No track items found in RecyclerView" -ForegroundColor Yellow
            return @()
        }
        
        Write-Host "Found $($trackNodes.Count) track items in RecyclerView`n" -ForegroundColor Green
        
        $index = 0
        foreach ($trackNode in $trackNodes) {
            $index++
            
            # Extract track information
            $titleNode = $trackNode.SelectSingleNode(".//node[@resource-id='com.dolby.dolby234:id/title_text_view']")
            $dateNode = $trackNode.SelectSingleNode(".//node[@resource-id='com.dolby.dolby234:id/date_text_view']")
            $timeNode = $trackNode.SelectSingleNode(".//node[@resource-id='com.dolby.dolby234:id/time_text_view']")
            
            $title = if ($titleNode) { $titleNode.GetAttribute('text') } else { "" }
            $date = if ($dateNode) { $dateNode.GetAttribute('text') } else { "" }
            $duration = if ($timeNode) { $timeNode.GetAttribute('text') } else { "" }
            $bounds = $trackNode.GetAttribute('bounds')
            $contentDesc = $trackNode.GetAttribute('content-desc')
            
            $item = [PSCustomObject]@{
                Index = $index
                Title = $title
                Date = $date
                Duration = $duration
                ContentDesc = $contentDesc
                Bounds = $bounds
            }
            
            $items += $item
            
            Write-Host "Item $($index):"
            Write-Host "  Title: $title" -ForegroundColor Yellow
            Write-Host "  Date: $date | Duration: $duration" -ForegroundColor Cyan
            Write-Host "  Bounds: $bounds" -ForegroundColor Gray
            Write-Host ""
        }
        
        return $items
    }
    catch {
        Write-Host "Error finding RecyclerView items: $_" -ForegroundColor Red
        return @()
    }
}

# Click on a track item by its bounds
function Click-TrackItem {
    param(
        [PSCustomObject]$Item
    )
    
    if ($null -eq $Item -or [string]::IsNullOrWhiteSpace($Item.Bounds)) {
        Write-Host "Invalid item or missing bounds" -ForegroundColor Red
        return $false
    }
    
    $center = Get-BoundsCenter -BoundsString $Item.Bounds
    
    if ($null -eq $center) {
        Write-Host "Failed to calculate center coordinates" -ForegroundColor Red
        return $false
    }
    
    Write-Host "`n=== Clicking on Item ===" -ForegroundColor Cyan
    Write-Host "Title: $($Item.Title)" -ForegroundColor Yellow
    Write-Host "Clicking at coordinates: ($($center.X), $($center.Y))" -ForegroundColor Green
    
    try {
        Invoke-Adb "shell input tap $($center.X) $($center.Y)"
        Write-Host "Click successful!" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Click failed: $_" -ForegroundColor Red
        return $false
    }
}

# ===================================================================
# AUTOMATION WORKFLOW FOR DOLBY ON APP
# ===================================================================
# Purpose: Navigate through Dolby On app's library and extract track information
# 
# Current Screen: Library view with RecyclerView showing list of audio recordings
# Package: com.dolby.dolby234
# 
# Key UI Elements:
# - RecyclerView ID: com.dolby.dolby234:id/library_items_recycler_view
# - Track Item ID: com.dolby.dolby234:id/swipe_layout (container for each track)
# - Title ID: com.dolby.dolby234:id/title_text_view
# - Date ID: com.dolby.dolby234:id/date_text_view  
# - Duration ID: com.dolby.dolby234:id/time_text_view
#
# Workflow:
# 1. Dump current UI (library screen)
# 2. Parse RecyclerView to find all track items
# 3. Click on first track item
# 4. Dump UI of the detail screen
# 5. Future: Extract export/share options from detail screen
# ===================================================================

Write-Host "`n" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DOLBY ON AUTOMATION - LIBRARY VIEW  " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Wait for app to stabilize
Start-Sleep -Seconds 2

# STEP 1: Get current UI dump (library screen)
Write-Host "`nSTEP 1: Dumping Library Screen UI..." -ForegroundColor Green
$xmlDump = Get-UiDump

if ($null -eq $xmlDump) {
    Write-Host "Failed to get UI dump. Exiting." -ForegroundColor Red
    exit 1
}
# Save library dump to file
$dumpsFolder = Join-Path $PSScriptRoot "dumps"
New-Item -ItemType Directory -Path $dumpsFolder -Force | Out-Null
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$libraryDumpPath = Join-Path $dumpsFolder "library_dump_$timestamp.xml"
$xmlDump | Set-Content -Path $libraryDumpPath -Encoding UTF8
Write-Host "Saved library XML to: $libraryDumpPath" -ForegroundColor Cyan
# STEP 2: Find all track items in RecyclerView
Write-Host "`nSTEP 2: Parsing RecyclerView Items..." -ForegroundColor Green
$trackItems = Get-RecyclerViewItems -XmlString $xmlDump

if ($trackItems.Count -eq 0) {
    Write-Host "No track items found. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host "Total tracks found: $($trackItems.Count)" -ForegroundColor Cyan

# STEP 3: Click on the first track item
Write-Host "`nSTEP 3: Clicking on First Track..." -ForegroundColor Green
$firstTrack = $trackItems[0]
$clickSuccess = Click-TrackItem -Item $firstTrack

if (-not $clickSuccess) {
    Write-Host "Failed to click on first track. Exiting." -ForegroundColor Red
    exit 1
}

# Wait for detail screen to load
Start-Sleep -Seconds 2

# STEP 4: Dump UI of the detail screen
Write-Host "`nSTEP 4: Dumping Track Detail Screen UI..." -ForegroundColor Green
$detailXmlDump = Get-UiDump

if ($null -eq $detailXmlDump) {
    Write-Host "Failed to get detail screen UI dump." -ForegroundColor Red
} else {
    Write-Host "Detail screen UI dumped successfully!" -ForegroundColor Green    
    # Save detail dump to file
    $detailDumpPath = Join-Path $dumpsFolder "detail_dump_$timestamp.xml"
    $detailXmlDump | Set-Content -Path $detailDumpPath -Encoding UTF8
    Write-Host "Saved detail XML to: $detailDumpPath" -ForegroundColor Cyan    
    # Parse and display elements from detail screen
    Write-Host "`n=== Detail Screen Elements ===" -ForegroundColor Cyan
    $detailElements = Parse-UiElements -XmlString $detailXmlDump
    
    Write-Host "Found $($detailElements.Count) UI elements on detail screen`n" -ForegroundColor Green
    
    # Display important elements (export/share buttons, etc.)
    foreach ($elem in $detailElements) {
        # Focus on interactive elements that might be export/share related
        if ($elem.Class -match 'Button|ImageView|ImageButton' -or 
            $elem.ContentDesc -match 'export|share|save|menu|more' -or
            $elem.ResourceId -match 'export|share|save|menu|more|action') {
            
            Write-Host "---" -ForegroundColor Yellow
            Write-Host "  Class: $($elem.Class)" -ForegroundColor White
            if (![string]::IsNullOrWhiteSpace($elem.Text)) {
                Write-Host "  Text: $($elem.Text)" -ForegroundColor Yellow
            }
            if (![string]::IsNullOrWhiteSpace($elem.ContentDesc)) {
                Write-Host "  Content-Desc: $($elem.ContentDesc)" -ForegroundColor Cyan
            }
            if (![string]::IsNullOrWhiteSpace($elem.ResourceId)) {
                Write-Host "  Resource-ID: $($elem.ResourceId)" -ForegroundColor Magenta
            }
            if (![string]::IsNullOrWhiteSpace($elem.Bounds)) {
                Write-Host "  Bounds: $($elem.Bounds)" -ForegroundColor Gray
            }
        }
    }
}

# STEP 5: Generate HTML Report
Write-Host "`nSTEP 8: Generating HTML Report..." -ForegroundColor Green

$htmlPath = Join-Path $dumpsFolder "report_$timestamp.html"

$htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='UTF-8'>
    <title>Dolby On Automation Report - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #4CAF50; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 30px; border-bottom: 2px solid #ddd; padding-bottom: 5px; }
        .track { background: #f9f9f9; padding: 15px; margin: 10px 0; border-left: 4px solid #2196F3; }
        .track-title { font-size: 18px; font-weight: bold; color: #2196F3; }
        .track-meta { color: #666; margin: 5px 0; }
        .element { background: #fff; padding: 10px; margin: 8px 0; border: 1px solid #ddd; border-radius: 3px; }
        .element.important { border-left: 4px solid #FF5722; background: #fff3e0; }
        .label { font-weight: bold; color: #555; }
        .value { color: #333; margin-left: 10px; }
        .class { color: #9C27B0; }
        .text { color: #FF9800; }
        .desc { color: #00BCD4; }
        .resource { color: #E91E63; }
        .bounds { color: #9E9E9E; font-size: 0.9em; }
        .summary { background: #e3f2fd; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .timestamp { color: #999; font-size: 0.9em; }
        .section { margin: 30px 0; }
    </style>
</head>
<body>
    <div class='container'>
        <h1>📱 Dolby On Automation Report</h1>
        <p class='timestamp'>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        
        <div class='summary'>
            <h3>📊 Summary</h3>
            <p><strong>Total Tracks Found:</strong> $($trackItems.Count)</p>
            <p><strong>First Track Clicked:</strong> $($firstTrack.Title)</p>
            <p><strong>Detail Screen Elements:</strong> $($detailElements.Count)</p>
            <p><strong>Share Popup Elements:</strong> $(if ($sharePopupElements) { $sharePopupElements.Count } else { 'N/A' })</p>
        </div>
        
        <div class='section'>
            <h2>📋 Library Screen - Track List</h2>
"@

foreach ($track in $trackItems) {
    $htmlContent += @"
            <div class='track'>
                <div class='track-title'>$($track.Index). $($track.Title)</div>
                <div class='track-meta'>📅 $($track.Date) | ⏱️ $($track.Duration)</div>
                <div class='track-meta'><span class='label'>Bounds:</span><span class='bounds'>$($track.Bounds)</span></div>
            </div>
"@
}

$htmlContent += @"
        </div>
        
        <div class='section'>
            <h2>🔍 Detail Screen - UI Elements</h2>
            <p>Showing interactive elements that may contain export/share functionality:</p>
"@

if ($detailElements.Count -eq 0) {
    $htmlContent += "<p style='color: #f44336;'>⚠️ No UI elements found on detail screen. This may indicate:</p>"
    $htmlContent += "<ul><li>The screen uses custom/canvas rendering (games, OpenGL)</li>"
    $htmlContent += "<li>UI dump timing issue - screen may not have loaded</li>"
    $htmlContent += "<li>Elements have no text/content-desc/resource-id attributes</li></ul>"
} else {
    foreach ($elem in $detailElements) {
        $isImportant = $elem.Class -match 'Button|ImageView|ImageButton' -or 
                       $elem.ContentDesc -match 'export|share|save|menu|more' -or
                       $elem.ResourceId -match 'export|share|save|menu|more|action'
        
        $elemClass = if ($isImportant) { 'element important' } else { 'element' }
        
        $htmlContent += "<div class='$elemClass'>"
        if (![string]::IsNullOrWhiteSpace($elem.Class)) {
            $htmlContent += "<div><span class='label'>Class:</span><span class='class value'>$($elem.Class)</span></div>"
        }
        if (![string]::IsNullOrWhiteSpace($elem.Text)) {
            $htmlContent += "<div><span class='label'>Text:</span><span class='text value'>$($elem.Text)</span></div>"
        }
        if (![string]::IsNullOrWhiteSpace($elem.ContentDesc)) {
            $htmlContent += "<div><span class='label'>Content-Desc:</span><span class='desc value'>$($elem.ContentDesc)</span></div>"
        }
        if (![string]::IsNullOrWhiteSpace($elem.ResourceId)) {
            $htmlContent += "<div><span class='label'>Resource-ID:</span><span class='resource value'>$($elem.ResourceId)</span></div>"
        }
        if (![string]::IsNullOrWhiteSpace($elem.Bounds)) {
            $htmlContent += "<div><span class='label'>Bounds:</span><span class='bounds value'>$($elem.Bounds)</span></div>"
        }
        $htmlContent += "</div>"
    }
}

$htmlContent += @"
        </div>
        
        <div class='section'>
            <h2>� Share Popup - UI Elements</h2>
"@

if ($null -eq $sharePopupElements -or $sharePopupElements.Count -eq 0) {
    $htmlContent += "<p style='color: #f44336;'>⚠️ No UI elements found in share popup. Possible reasons:</p>"
    $htmlContent += "<ul><li>Share button was not clicked successfully</li>"
    $htmlContent += "<li>Popup did not appear or took too long to load</li>"
    $htmlContent += "<li>Popup uses custom rendering</li></ul>"
} else {
    $htmlContent += "<p>All elements from the share/export popup:</p>"
    foreach ($elem in $sharePopupElements) {
        $isImportant = $elem.Text -match 'export|save|wav|mp3|share|dolby' -or
                       $elem.ContentDesc -match 'export|save|wav|mp3|share|dolby' -or
                       $elem.ResourceId -match 'export|save|wav|mp3|share|dolby'
        
        $elemClass = if ($isImportant) { 'element important' } else { 'element' }
        
        $htmlContent += "<div class='$elemClass'>"
        if (![string]::IsNullOrWhiteSpace($elem.Class)) {
            $htmlContent += "<div><span class='label'>Class:</span><span class='class value'>$($elem.Class)</span></div>"
        }
        if (![string]::IsNullOrWhiteSpace($elem.Text)) {
            $htmlContent += "<div><span class='label'>Text:</span><span class='text value'>$($elem.Text)</span></div>"
        }
        if (![string]::IsNullOrWhiteSpace($elem.ContentDesc)) {
            $htmlContent += "<div><span class='label'>Content-Desc:</span><span class='desc value'>$($elem.ContentDesc)</span></div>"
        }
        if (![string]::IsNullOrWhiteSpace($elem.ResourceId)) {
            $htmlContent += "<div><span class='label'>Resource-ID:</span><span class='resource value'>$($elem.ResourceId)</span></div>"
        }
        if (![string]::IsNullOrWhiteSpace($elem.Bounds)) {
            $htmlContent += "<div><span class='label'>Bounds:</span><span class='bounds value'>$($elem.Bounds)</span></div>"
        }
        $htmlContent += "</div>"
    }
}

$htmlContent += @"
        </div>
        
        <div class='section'>
            <h2>📁 Generated Files</h2>
            <ul>
                <li>Library XML: <code>library_dump_$timestamp.xml</code></li>
                <li>Detail XML: <code>detail_dump_$timestamp.xml</code></li>
                <li>Share Popup XML: <code>share_popup_dump_$timestamp.xml</code></li>
                <li>This Report: <code>report_$timestamp.html</code></li>
            </ul>
        </div>
        
        <div class='section'>
            <h2>🎯 Next Steps</h2>
            <ol>
                <li>Review share popup elements for export/save options</li>
                <li>Look for buttons with text like: Export, Save As, WAV, MP3, etc.</li>
                <li>Check if Dolby processing toggle appears in export options</li>
                <li>Identify the correct flow: Export -> Format selection -> Dolby toggle</li>
                <li>Add automation to complete the export with Dolby enabled</li>
            </ol>
        </div>
    </div>
</body>
</html>
"@

$htmlContent | Set-Content -Path $htmlPath -Encoding UTF8
Write-Host "HTML report saved to: $htmlPath" -ForegroundColor Green

Write-Host "\n" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  AUTOMATION COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📁 Files Generated:" -ForegroundColor Yellow
Write-Host "  - $libraryDumpPath" -ForegroundColor White
Write-Host "  - $detailDumpPath" -ForegroundColor White
if ($sharePopupDumpPath) {
    Write-Host "  - $sharePopupDumpPath" -ForegroundColor White
}
Write-Host "  - $htmlPath" -ForegroundColor White
Write-Host ""
Write-Host "💡 Open the HTML report in your browser to review!" -ForegroundColor Green
Write-Host ""

# STEP 6: Click Share Button
Write-Host "`nSTEP 6: Clicking Share Button..." -ForegroundColor Green

# Find Share button from detail screen
try {
    [xml]$detailXml = $detailXmlDump
    $shareButton = $detailXml.SelectSingleNode("//node[@resource-id='com.dolby.dolby234:id/track_details_share']")
    
    if ($null -eq $shareButton) {
        Write-Host "Share button not found in detail screen!" -ForegroundColor Red
    } else {
        $shareBounds = $shareButton.GetAttribute('bounds')
        Write-Host "Found Share button with bounds: $shareBounds" -ForegroundColor Cyan
        
        $shareCenter = Get-BoundsCenter -BoundsString $shareBounds
        
        if ($null -ne $shareCenter) {
            Write-Host "Clicking Share at coordinates: ($($shareCenter.X), $($shareCenter.Y))" -ForegroundColor Green
            Invoke-Adb "shell input tap $($shareCenter.X) $($shareCenter.Y)"
            Write-Host "Share button clicked!" -ForegroundColor Green
            
            # Wait for share popup/dialog to appear
            Start-Sleep -Seconds 2
            
            # STEP 7: Dump the share popup UI
            Write-Host "`nSTEP 7: Dumping Share Popup UI..." -ForegroundColor Green
            $sharePopupXmlDump = Get-UiDump
            
            if ($null -eq $sharePopupXmlDump) {
                Write-Host "Failed to get share popup UI dump." -ForegroundColor Red
            } else {
                Write-Host "Share popup UI dumped successfully!" -ForegroundColor Green
                
                # Save share popup dump to file
                $sharePopupDumpPath = Join-Path $dumpsFolder "share_popup_dump_$timestamp.xml"
                $sharePopupXmlDump | Set-Content -Path $sharePopupDumpPath -Encoding UTF8
                Write-Host "Saved share popup XML to: $sharePopupDumpPath" -ForegroundColor Cyan
                
                # Parse and display share popup elements
                Write-Host "`n=== Share Popup Elements ===" -ForegroundColor Cyan
                $sharePopupElements = Parse-UiElements -XmlString $sharePopupXmlDump
                
                Write-Host "Found $($sharePopupElements.Count) UI elements in share popup`n" -ForegroundColor Green
                
                # Display all elements to help identify export options
                foreach ($elem in $sharePopupElements) {
                    Write-Host "---" -ForegroundColor Yellow
                    if (![string]::IsNullOrWhiteSpace($elem.Class)) {
                        Write-Host "  Class: $($elem.Class)" -ForegroundColor White
                    }
                    if (![string]::IsNullOrWhiteSpace($elem.Text)) {
                        Write-Host "  Text: $($elem.Text)" -ForegroundColor Yellow
                    }
                    if (![string]::IsNullOrWhiteSpace($elem.ContentDesc)) {
                        Write-Host "  Content-Desc: $($elem.ContentDesc)" -ForegroundColor Cyan
                    }
                    if (![string]::IsNullOrWhiteSpace($elem.ResourceId)) {
                        Write-Host "  Resource-ID: $($elem.ResourceId)" -ForegroundColor Magenta
                    }
                    if (![string]::IsNullOrWhiteSpace($elem.Bounds)) {
                        Write-Host "  Bounds: $($elem.Bounds)" -ForegroundColor Gray
                    }
                }
            }
        } else {
            Write-Host "Failed to calculate Share button center coordinates." -ForegroundColor Red
        }
    }
}
catch {
    Write-Host "Error clicking Share button: $_" -ForegroundColor Red
}

# For future AI agents:
# - The detail screen UI dump is stored in $detailXmlDump
# - The share popup UI dump is stored in $sharePopupXmlDump
# - Look for export/save options in the share popup
# - Common flow: Share popup -> Export/Save As -> Select format -> Enable Dolby processing
# - Check for buttons with text like: Export, Save, Save As, WAV, MP3, etc.

