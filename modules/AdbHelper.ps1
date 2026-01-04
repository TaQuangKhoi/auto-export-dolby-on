# ===================================================================
# ADBHELPER.PS1 - ADB Connection & Execution
# ===================================================================
# Handles finding ADB executable and executing commands

function Find-Adb {
    <#
    .SYNOPSIS
    Locates adb executable in system PATH or Android SDK
    
    .DESCRIPTION
    Searches for adb in the following order:
    1. System PATH
    2. ADB_PATH environment variable
    3. ANDROID_HOME/platform-tools
    4. ANDROID_SDK_ROOT/platform-tools
    #>
    
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

function Initialize-Adb {
    <#
    .SYNOPSIS
    Finds ADB and validates it's available
    
    .DESCRIPTION
    Locates ADB executable and throws error if not found
    #>
    
    $adb = Find-Adb
    
    if (-not $adb) {
        Write-Host "Error: 'adb' executable not found." -ForegroundColor Red
        Write-Host "Install Android Platform-tools and add 'adb' to your PATH," -ForegroundColor Red
        Write-Host "or set environment variable ADB_PATH, ANDROID_HOME, or ANDROID_SDK_ROOT." -ForegroundColor Red
        throw "ADB not found"
    }
    
    Write-Host "✓ ADB found: $adb" -ForegroundColor Green
    return $adb
}

function Invoke-Adb {
    <#
    .SYNOPSIS
    Executes an ADB command
    
    .PARAMETER Command
    The ADB command to execute (without 'adb' prefix)
    
    .PARAMETER AdbPath
    Path to ADB executable
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        
        [Parameter(Mandatory)]
        [string]$AdbPath
    )

    $fullCommand = "$AdbPath $Command"

    try {
        Invoke-Expression $fullCommand
        if ($LASTEXITCODE -ne 0) {
            throw "Command returned exit code $LASTEXITCODE"
        }
    }
    catch {
        Write-Host "Error executing: $fullCommand" -ForegroundColor Red
        throw
    }
}
