# ===================================================================
# UIAUTOMATOR.PS1 - UI Dumping & Parsing
# ===================================================================
# Handles UI hierarchy dumping and XML parsing

function Get-UiDump {
    <#
    .SYNOPSIS
    Dumps current UI hierarchy from Android device
    
    .PARAMETER AdbPath
    Path to ADB executable
    
    .OUTPUTS
    XML string containing UI hierarchy
    #>
    param(
        [Parameter(Mandatory)]
        [string]$AdbPath
    )
    
    Write-Host "Dumping UI hierarchy..." -ForegroundColor Cyan
    
    try {
        # Use exec-out to dump directly to console (no file needed)
        $xmlOutput = & $AdbPath exec-out uiautomator dump /dev/tty 2>&1
        
        # Convert to string if array
        $fullOutput = $xmlOutput -join "`n"
        
        # Extract only the XML portion (from <?xml or <hierarchy to </hierarchy>)
        if ($fullOutput -match '(<\?xml.*?<hierarchy.*?</hierarchy>)') {
            return $matches[1]
        }
        elseif ($fullOutput -match '(<hierarchy.*?</hierarchy>)') {
            return $matches[1]
        }
        else {
            Write-Host "Warning: No valid XML hierarchy found in output" -ForegroundColor Yellow
            Write-Host "Output preview: $($fullOutput.Substring(0, [Math]::Min(200, $fullOutput.Length)))" -ForegroundColor Yellow
            return $null
        }
    }
    catch {
        Write-Host "Error dumping UI: $_" -ForegroundColor Red
        return $null
    }
}

function ConvertFrom-UiXml {
    <#
    .SYNOPSIS
    Parses UI XML and extracts elements with text/content-desc/resource-id
    
    .PARAMETER XmlString
    XML string from UI dump
    
    .OUTPUTS
    Array of UI elements with properties: Class, Text, ContentDesc, ResourceId, Bounds
    #>
    param(
        [Parameter(Mandatory)]
        [string]$XmlString
    )
    
    if ([string]::IsNullOrWhiteSpace($XmlString)) {
        Write-Host "No XML to parse" -ForegroundColor Yellow
        return @()
    }
    
    try {
        [xml]$xmlDoc = $XmlString
        $elements = @()
        
        # Recursively traverse all nodes
        function Process-Node {
            param($node)
            
            if ($node.NodeType -eq 'Element') {
                $text = $node.GetAttribute('text')
                $contentDesc = $node.GetAttribute('content-desc')
                $resourceId = $node.GetAttribute('resource-id')
                $className = $node.GetAttribute('class')
                $bounds = $node.GetAttribute('bounds')
                
                # Only include elements with identifiable properties
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
        
        Write-Host "✓ Parsed $($elements.Count) UI elements" -ForegroundColor Green
        return $elements
    }
    catch {
        Write-Host "Error parsing XML: $_" -ForegroundColor Red
        return @()
    }
}

function Save-UiDump {
    <#
    .SYNOPSIS
    Saves UI dump XML to file
    
    .PARAMETER XmlContent
    XML string to save
    
    .PARAMETER OutputPath
    File path to save to
    #>
    param(
        [Parameter(Mandatory)]
        [string]$XmlContent,
        
        [Parameter(Mandatory)]
        [string]$OutputPath
    )
    
    try {
        $dir = Split-Path -Parent $OutputPath
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        
        $XmlContent | Set-Content -Path $OutputPath -Encoding UTF8
        Write-Host "✓ Saved UI dump: $OutputPath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Error saving dump: $_" -ForegroundColor Red
        return $false
    }
}

function Wait-ForExportCompletion {
    <#
    .SYNOPSIS
    Smart waiting for export completion by detecting Save Dialog appearance
    
    .PARAMETER AdbPath
    Path to ADB executable
    
    .PARAMETER MaxWaitSeconds
    Maximum time to wait for export (default: 300 seconds = 5 minutes)
    
    .PARAMETER CheckIntervalSeconds
    How often to check UI (default: 2 seconds)
    
    .OUTPUTS
    XML string of Save Dialog if found, $null if timeout
    #>
    param(
        [Parameter(Mandatory)]
        [string]$AdbPath,
        
        [int]$MaxWaitSeconds = 300,
        [int]$CheckIntervalSeconds = 2
    )
    
    Write-Host "Monitoring export progress..." -ForegroundColor Cyan
    Write-Host "  Looking for Save Dialog to appear..." -ForegroundColor Gray
    
    $startTime = Get-Date
    $exportStarted = $false
    
    while (((Get-Date) - $startTime).TotalSeconds -lt $MaxWaitSeconds) {
        try {
            # Get current UI state
            $xmlOutput = & $AdbPath exec-out uiautomator dump /dev/tty 2>&1
            $fullOutput = $xmlOutput -join "`n"
            
            # Extract XML
            $xmlString = $null
            if ($fullOutput -match '(<\?xml.*?<hierarchy.*?</hierarchy>)') {
                $xmlString = $matches[1]
            }
            elseif ($fullOutput -match '(<hierarchy.*?</hierarchy>)') {
                $xmlString = $matches[1]
            }
            
            if ($xmlString) {
                # Check for Save Dialog indicators (Android DocumentsUI)
                $hasSaveDialog = $false
                
                # Look for DocumentsUI package
                if ($xmlString -match 'com\.android\.documentsui') {
                    $hasSaveDialog = $true
                }
                
                # Look for common Save Dialog elements
                if ($xmlString -match 'text="Save"|content-desc="Save"') {
                    $hasSaveDialog = $true
                }
                
                # Look for "Drive" option (indicates save location chooser)
                if ($xmlString -match 'text="Drive"|content-desc="Drive"') {
                    $hasSaveDialog = $true
                }
                
                if ($hasSaveDialog) {
                    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
                    Write-Host "✓ Save Dialog appeared! Export completed in $elapsed seconds" -ForegroundColor Green
                    return $xmlString
                }
                
                # Check if still exporting (progress indicators)
                $isExporting = $false
                if ($xmlString -match 'ProgressBar|progress|android\.widget\.ProgressBar') {
                    $isExporting = $true
                }
                if ($xmlString -match 'text="[^"]*(?:Export|Process)[^"]*"') {
                    $isExporting = $true
                }
                
                if ($isExporting) {
                    if (-not $exportStarted) {
                        Write-Host "  ⏳ Export started..." -ForegroundColor Yellow
                        $exportStarted = $true
                    }
                    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
                    Write-Host "  ⏳ Exporting... ($elapsed seconds)" -ForegroundColor Yellow
                }
                else {
                    # No progress bar, no save dialog yet
                    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
                    Write-Host "  ⏳ Waiting for export to start... ($elapsed seconds)" -ForegroundColor Gray
                }
            }
            else {
                # Device busy
                Write-Host "  ⏳ Device busy, retrying..." -ForegroundColor Gray
            }
            
            Start-Sleep -Seconds $CheckIntervalSeconds
        }
        catch {
            Write-Host "  Warning: Error during check: $_" -ForegroundColor Yellow
            Start-Sleep -Seconds $CheckIntervalSeconds
        }
    }
    
    # Timeout
    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
    Write-Host "⚠️ Timeout after $elapsed seconds - Save Dialog did not appear" -ForegroundColor Yellow
    return $null
}
