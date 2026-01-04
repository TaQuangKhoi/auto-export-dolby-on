# ===================================================================
# DOLBYAPPHELPER.PS1 - Dolby App Specific Functions
# ===================================================================
# Contains app-specific logic for navigating Dolby On app

. "$PSScriptRoot\Config.ps1"

function Get-TrackList {
    <#
    .SYNOPSIS
    Extracts list of tracks from library RecyclerView
    
    .PARAMETER XmlString
    UI dump XML containing library screen
    
    .OUTPUTS
    Array of track objects with Title, Date, Duration, Bounds
    #>
    param(
        [Parameter(Mandatory)]
        [string]$XmlString
    )
    
    Write-Host "Parsing track list from RecyclerView..." -ForegroundColor Cyan
    
    if ([string]::IsNullOrWhiteSpace($XmlString)) {
        Write-Host "No XML provided" -ForegroundColor Red
        return @()
    }
    
    try {
        $config = Get-Config
        [xml]$xmlDoc = $XmlString
        
        # Find RecyclerView containing tracks
        $recyclerViewId = $config.DolbyApp.ResourceIds.RecyclerView
        $recyclerView = $xmlDoc.SelectSingleNode("//node[@resource-id='$recyclerViewId']")
        
        if ($null -eq $recyclerView) {
            Write-Host "RecyclerView not found: $recyclerViewId" -ForegroundColor Red
            return @()
        }
        
        # Find all track item containers
        $trackItemId = $config.DolbyApp.ResourceIds.TrackItem
        $trackNodes = $recyclerView.SelectNodes(".//node[@resource-id='$trackItemId']")
        
        if ($null -eq $trackNodes -or $trackNodes.Count -eq 0) {
            Write-Host "No track items found" -ForegroundColor Yellow
            return @()
        }
        
        $tracks = @()
        $index = 0
        
        foreach ($trackNode in $trackNodes) {
            $index++
            
            # Extract track metadata
            $titleNode = $trackNode.SelectSingleNode(".//node[@resource-id='$($config.DolbyApp.ResourceIds.Title)']")
            $dateNode = $trackNode.SelectSingleNode(".//node[@resource-id='$($config.DolbyApp.ResourceIds.Date)']")
            $timeNode = $trackNode.SelectSingleNode(".//node[@resource-id='$($config.DolbyApp.ResourceIds.Time)']")
            
            $track = [PSCustomObject]@{
                Index = $index
                Title = if ($titleNode) { $titleNode.GetAttribute('text') } else { "(No Title)" }
                Date = if ($dateNode) { $dateNode.GetAttribute('text') } else { "" }
                Duration = if ($timeNode) { $timeNode.GetAttribute('text') } else { "" }
                Bounds = $trackNode.GetAttribute('bounds')
            }
            
            $tracks += $track
            
            Write-Host "  Track $index : $($track.Title) - $($track.Duration)" -ForegroundColor Gray
        }
        
        Write-Host "✓ Found $($tracks.Count) tracks" -ForegroundColor Green
        return $tracks
    }
    catch {
        Write-Host "Error parsing track list: $_" -ForegroundColor Red
        return @()
    }
}

function Find-UiElement {
    <#
    .SYNOPSIS
    Finds UI element by resource-id, text, or content-desc
    
    .PARAMETER XmlString
    UI dump XML to search
    
    .PARAMETER ResourceId
    Resource ID to search for
    
    .PARAMETER Text
    Text attribute to search for
    
    .PARAMETER ContentDesc
    Content description to search for
    
    .OUTPUTS
    Hashtable with Bounds, Text, ResourceId properties (or $null if not found)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$XmlString,
        
        [string]$ResourceId = $null,
        [string]$Text = $null,
        [string]$ContentDesc = $null
    )
    
    if ([string]::IsNullOrWhiteSpace($XmlString)) {
        return $null
    }
    
    try {
        [xml]$xmlDoc = $XmlString
        $node = $null
        
        if ($ResourceId) {
            $node = $xmlDoc.SelectSingleNode("//node[@resource-id='$ResourceId']")
        }
        elseif ($Text) {
            $node = $xmlDoc.SelectSingleNode("//node[@text='$Text']")
        }
        elseif ($ContentDesc) {
            $node = $xmlDoc.SelectSingleNode("//node[@content-desc='$ContentDesc']")
        }
        
        if ($node) {
            return @{
                Bounds = $node.GetAttribute('bounds')
                Text = $node.GetAttribute('text')
                ContentDesc = $node.GetAttribute('content-desc')
                ResourceId = $node.GetAttribute('resource-id')
                Class = $node.GetAttribute('class')
            }
        }
        
        return $null
    }
    catch {
        Write-Host "Error finding UI element: $_" -ForegroundColor Red
        return $null
    }
}
