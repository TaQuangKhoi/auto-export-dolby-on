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

Export-ModuleMember -Function Get-UiDump, ConvertFrom-UiXml, Save-UiDump
