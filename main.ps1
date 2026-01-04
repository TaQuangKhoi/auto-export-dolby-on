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

# Main automation sequence
Invoke-Adb "shell input keyevent 3"        # Home
Start-Sleep -Seconds 1
Invoke-Adb "shell input tap 540 2100"      # ví dụ: mở app ở dock
Start-Sleep -Seconds 2
Invoke-Adb 'shell input text "hello%sworld"'
Invoke-Adb "shell input keyevent 66"       # Enter

