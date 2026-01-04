# ===================================================================
# COORDINATES.PS1 - Bounds Calculation & Clicking
# ===================================================================
# Handles coordinate calculation from bounds and tap actions

function Get-BoundsCenter {
    <#
    .SYNOPSIS
    Calculates center coordinates from Android bounds string
    
    .PARAMETER BoundsString
    Bounds string in format [x1,y1][x2,y2]
    
    .OUTPUTS
    Hashtable with X and Y coordinates
    #>
    param(
        [Parameter(Mandatory)]
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
    
    Write-Host "Warning: Invalid bounds format: $BoundsString" -ForegroundColor Yellow
    return $null
}

function Invoke-TapAt {
    <#
    .SYNOPSIS
    Taps at specific coordinates on Android device
    
    .PARAMETER Coordinates
    Hashtable with X and Y properties
    
    .PARAMETER AdbPath
    Path to ADB executable
    
    .PARAMETER Description
    Human-readable description of what's being tapped
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Coordinates,
        
        [Parameter(Mandatory)]
        [string]$AdbPath,
        
        [string]$Description = "element"
    )
    
    if ($null -eq $Coordinates) {
        Write-Host "Error: Cannot tap - coordinates are null" -ForegroundColor Red
        return $false
    }
    
    $x = $Coordinates.X
    $y = $Coordinates.Y
    
    Write-Host "→ Tapping $Description at ($x, $y)" -ForegroundColor Green
    
    try {
        & $AdbPath shell input tap $x $y
        if ($LASTEXITCODE -ne 0) {
            throw "Tap command failed with exit code $LASTEXITCODE"
        }
        return $true
    }
    catch {
        Write-Host "Error tapping at ($x, $y): $_" -ForegroundColor Red
        return $false
    }
}

function Invoke-TapElement {
    <#
    .SYNOPSIS
    Taps on UI element by calculating center from bounds
    
    .PARAMETER Element
    UI element object with Bounds property
    
    .PARAMETER AdbPath
    Path to ADB executable
    
    .PARAMETER Description
    Human-readable description of the element
    #>
    param(
        [Parameter(Mandatory)]
        [object]$Element,
        
        [Parameter(Mandatory)]
        [string]$AdbPath,
        
        [string]$Description = "element"
    )
    
    if ($null -eq $Element -or [string]::IsNullOrWhiteSpace($Element.Bounds)) {
        Write-Host "Error: Element or bounds is null" -ForegroundColor Red
        return $false
    }
    
    $center = Get-BoundsCenter -BoundsString $Element.Bounds
    
    if ($null -eq $center) {
        Write-Host "Error: Could not calculate center for bounds: $($Element.Bounds)" -ForegroundColor Red
        return $false
    }
    
    return Invoke-TapAt -Coordinates $center -AdbPath $AdbPath -Description $Description
}

Export-ModuleMember -Function Get-BoundsCenter, Invoke-TapAt, Invoke-TapElement
