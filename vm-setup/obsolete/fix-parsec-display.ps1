. "$PSScriptRoot\config.ps1"

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {

    Write-Host "=== Parsec log.txt (last 50 lines) ===" -ForegroundColor Cyan
    $log = "C:\Users\bot\AppData\Roaming\Parsec\log.txt"
    if (Test-Path $log) {
        Get-Content $log -Tail 50 | ForEach-Object { Write-Host $_ }
    }

    Write-Host ""
    Write-Host "=== config.json ===" -ForegroundColor Cyan
    Get-Content "C:\Users\bot\AppData\Roaming\Parsec\config.json" | ConvertFrom-Json | Format-List

    Write-Host ""
    Write-Host "=== Installing Parsec Virtual Display Driver ===" -ForegroundColor Cyan
    # VDD creates a virtual monitor on the NVIDIA GPU so Parsec can use NVENC
    $vdd = "C:\Program Files\Parsec\vdd\parsec-vdd.exe"
    if (Test-Path $vdd) {
        Write-Host "  Running parsec-vdd.exe --install..."
        $result = Start-Process $vdd -ArgumentList "--install" -Wait -PassThru -NoNewWindow
        Write-Host "  Exit code: $($result.ExitCode)"
        Start-Sleep 3

        Write-Host "  Starting VDD service..."
        Start-Process $vdd -ArgumentList "--start" -Wait -NoNewWindow -ErrorAction SilentlyContinue
        Start-Sleep 2
    } else {
        Write-Host "  parsec-vdd.exe not found!" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "=== Display devices after VDD install ===" -ForegroundColor Cyan
    Get-PnpDevice -Class Display | Format-Table FriendlyName, Status, InstanceId -AutoSize
    Get-WmiObject Win32_VideoController | Format-Table Name, CurrentHorizontalResolution, CurrentVerticalResolution, Status

    Write-Host ""
    Write-Host "=== Display monitors ===" -ForegroundColor Cyan
    Get-WmiObject Win32_DesktopMonitor | Format-Table Name, ScreenWidth, ScreenHeight, Status

    Write-Host ""
    Write-Host "=== Restarting Parsec ===" -ForegroundColor Cyan
    Get-Process parsecd -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep 2
    Start-Process "C:\Program Files\Parsec\parsecd.exe"
    Start-Sleep 5
    Get-Process parsecd -ErrorAction SilentlyContinue | Format-Table Name, Id, Responding
}
