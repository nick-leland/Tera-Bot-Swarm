. "$PSScriptRoot\config.ps1"
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host "=== DXGI MaxFeatureLevel ===" -ForegroundColor Cyan
    Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\DirectX" | Select-Object MaxFeatureLevel, Version

    Write-Host ""
    Write-Host "=== VirtualRender service ===" -ForegroundColor Cyan
    Get-Service VirtualRender -ErrorAction SilentlyContinue | Format-Table Status, StartType, Name

    Write-Host ""
    Write-Host "=== Display class registry ===" -ForegroundColor Cyan
    Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}" |
        Where-Object { $_.PSChildName -match "^\d+$" } | ForEach-Object {
            $v = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            [PSCustomObject]@{Key=$_.PSChildName; Driver=$v.DriverDesc; Service=$v.Service}
        } | Format-Table

    Write-Host ""
    Write-Host "=== GPU in Win32_VideoController ===" -ForegroundColor Cyan
    Get-WmiObject Win32_VideoController | Format-Table Name, VideoProcessor, AdapterRAM, Status

    Write-Host ""
    Write-Host "=== dxgkrnl events (last 5) ===" -ForegroundColor Cyan
    Get-WinEvent -LogName System -MaxEvents 200 -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -like "*dxg*" -or $_.Message -like "*dxgkrnl*" -or $_.Message -like "*VirtualRender*" } |
        Select-Object -Last 5 | Format-Table TimeCreated, Id, Message -Wrap

    Write-Host ""
    Write-Host "=== Parsec process ===" -ForegroundColor Cyan
    Get-Process -Name "parsecd*" -ErrorAction SilentlyContinue | Format-Table Name, Id, Responding
}
