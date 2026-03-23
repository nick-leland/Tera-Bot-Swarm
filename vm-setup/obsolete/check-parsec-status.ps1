. "$PSScriptRoot\config.ps1"

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {

    Write-Host "=== Parsec config/log files ===" -ForegroundColor Cyan
    $searchPaths = @(
        "$env:APPDATA\Parsec",
        "$env:LOCALAPPDATA\Parsec",
        "$env:PROGRAMDATA\Parsec",
        "C:\Program Files\Parsec"
    )
    foreach ($p in $searchPaths) {
        if (Test-Path $p) {
            Write-Host "  $p :"
            Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue |
                Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize
        }
    }

    Write-Host ""
    Write-Host "=== Parsec config (config.txt if exists) ===" -ForegroundColor Cyan
    $cfgCandidates = @(
        "$env:APPDATA\Parsec\config.txt",
        "$env:LOCALAPPDATA\Parsec\config.txt",
        "$env:PROGRAMDATA\Parsec\config.txt"
    )
    foreach ($c in $cfgCandidates) {
        if (Test-Path $c) {
            Write-Host "  Found: $c"
            Get-Content $c | ForEach-Object { Write-Host "    $_" }
        }
    }

    Write-Host ""
    Write-Host "=== Parsec log (search all) ===" -ForegroundColor Cyan
    Get-ChildItem "C:\" -Recurse -Filter "parsec.log" -ErrorAction SilentlyContinue |
        Select-Object -First 3 | ForEach-Object {
            Write-Host "  Log: $($_.FullName)"
            Get-Content $_.FullName -Tail 30 | ForEach-Object { Write-Host "  $_" }
        }

    Write-Host ""
    Write-Host "=== Which GPU is the primary display adapter ===" -ForegroundColor Cyan
    # Check which adapter has the active display output
    Get-WmiObject Win32_VideoController | Format-Table Name, DeviceID, CurrentHorizontalResolution, CurrentVerticalResolution, VideoModeDescription, Status

    Write-Host ""
    Write-Host "=== GPU encoder availability (NVENC check) ===" -ForegroundColor Cyan
    # Check if NVIDIA NVENC is listed in available codecs
    $nvEncKey = "HKLM:\SOFTWARE\NVIDIA Corporation\NvCplApi\Policies"
    if (Test-Path $nvEncKey) {
        Get-ItemProperty $nvEncKey | Format-List
    }
    # NVIDIA driver info
    Get-WmiObject Win32_PnPSignedDriver | Where-Object { $_.DeviceName -like "*NVIDIA*RTX*" } |
        Select-Object DeviceName, DriverVersion, DriverDate | Format-Table
}
