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
        
        # Filter out non-XML lines (uiautomator outputs status messages)
        $xmlLines = $xmlOutput | Where-Object { $_ -match '<.*>' }
        $xmlString = $xmlLines -join "`n"
        
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

# Main automation sequence (stay in the current app; do not navigate to Home)
# If you need to open the app via tap, uncomment the line below
# Invoke-Adb "shell input tap 540 2100"      # ví dụ: mở app ở dock
Start-Sleep -Seconds 2

# Get UI text from current screen
$uiElements = Get-ScreenText

# Example: Continue with text input
# Invoke-Adb 'shell input text "hello%sworld"'
# Invoke-Adb "shell input keyevent 66"       # Enter

