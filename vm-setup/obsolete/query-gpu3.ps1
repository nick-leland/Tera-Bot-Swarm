. "$PSScriptRoot\config.ps1"

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host "=== BCD boot settings ===" -ForegroundColor Cyan
    bcdedit /enum | Select-String "testsigning|nointegrity|bootmenupolicy"

    Write-Host ""
    Write-Host "=== Secure Boot status ===" -ForegroundColor Cyan
    try { Confirm-SecureBootUEFI } catch { Write-Host "  Error: $_" }

    Write-Host ""
    Write-Host "=== Staged NVIDIA driver packages ===" -ForegroundColor Cyan
    pnputil /enum-drivers 2>&1 | Out-String | Select-String -Pattern "nv_dispi|NVIDIA|oem\d+" -Context 0,5

    Write-Host ""
    Write-Host "=== DriverDatabase VEN_1414 entry ===" -ForegroundColor Cyan
    Get-ItemProperty "HKLM:\SYSTEM\DriverDatabase\DeviceIds\PCI\VEN_1414&DEV_008E" -ErrorAction SilentlyContinue
}
