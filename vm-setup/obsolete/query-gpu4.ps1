. "$PSScriptRoot\config.ps1"

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host "=== BCD state ===" -ForegroundColor Cyan
    bcdedit /enum | Select-String "testsigning|nointegrity|loadoption"

    Write-Host ""
    Write-Host "=== Staged OEM drivers (display-related) ===" -ForegroundColor Cyan
    pnputil /enum-drivers 2>&1 | Out-String | Select-String -Pattern "oem\d+\.inf|Display|NVIDIA|nv_" -Context 0,3

    Write-Host ""
    Write-Host "=== oem4.inf content ===" -ForegroundColor Cyan
    $oem4 = "C:\Windows\INF\oem4.inf"
    if (Test-Path $oem4) {
        Get-Content $oem4 | Select-Object -First 30
    } else {
        Write-Host "oem4.inf not found - checking what oem files exist:"
        Get-ChildItem "C:\Windows\INF" -Filter "oem*.inf" | Sort-Object Name | Select-Object -Last 10 | ForEach-Object { Write-Host "  $($_.Name)" }
    }

    Write-Host ""
    Write-Host "=== DriverDatabase VEN_1414 entry ===" -ForegroundColor Cyan
    $path = "HKLM:\SYSTEM\DriverDatabase\DeviceIds\PCI\VEN_1414&DEV_008E"
    if (Test-Path $path) {
        Get-ItemProperty $path
    } else {
        Write-Host "  (not found - VEN_1414 not in DriverDatabase)"
    }
}
