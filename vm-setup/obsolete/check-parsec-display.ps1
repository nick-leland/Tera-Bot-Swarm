. "$PSScriptRoot\config.ps1"

$timeout = 60; $elapsed = 0
while ($elapsed -lt $timeout) {
    try {
        Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { 1 } -ErrorAction Stop | Out-Null
        break
    } catch { Start-Sleep 10; $elapsed += 10 }
}

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {

    Write-Host "=== All display devices ===" -ForegroundColor Cyan
    Get-PnpDevice -Class Display | Format-Table FriendlyName, Status, InstanceId -AutoSize

    Write-Host ""
    Write-Host "=== Parsec Virtual Display (if installed) ===" -ForegroundColor Cyan
    Get-PnpDevice | Where-Object { $_.FriendlyName -like "*Parsec*" -or $_.InstanceId -like "*Parsec*" } |
        Format-Table FriendlyName, Status, InstanceId -AutoSize

    Write-Host ""
    Write-Host "=== Active monitors/displays ===" -ForegroundColor Cyan
    Get-WmiObject Win32_DesktopMonitor | Format-Table Name, ScreenWidth, ScreenHeight, Status

    Write-Host ""
    Write-Host "=== Parsec process + exe location ===" -ForegroundColor Cyan
    $parsec = Get-Process parsecd -ErrorAction SilentlyContinue
    if ($parsec) {
        $parsec | Format-Table Name, Id, Path
    } else {
        Write-Host "  Parsec not running - checking install locations..."
        $locations = @(
            "$env:LOCALAPPDATA\Parsec\parsecd.exe",
            "$env:PROGRAMFILES\Parsec\parsecd.exe",
            "${env:PROGRAMFILES(X86)}\Parsec\parsecd.exe"
        )
        $found = $locations | Where-Object { Test-Path $_ }
        $found | ForEach-Object { Write-Host "  Found: $_" }

        if ($found) {
            Write-Host "  Starting Parsec..."
            Start-Process $found[0]
            Start-Sleep 5
            Get-Process parsecd -ErrorAction SilentlyContinue | Format-Table Name, Id
        }
    }

    Write-Host ""
    Write-Host "=== Parsec log (last 20 lines) ===" -ForegroundColor Cyan
    $logPaths = @(
        "$env:APPDATA\Parsec\parsec.log",
        "$env:LOCALAPPDATA\Parsec\parsec.log"
    )
    $log = $logPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($log) {
        Get-Content $log -Tail 20 | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "  No log found"
    }
}
