. "$PSScriptRoot\config.ps1"

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host "=== oem2.inf - searching for VEN_1414 / DEV_008E ===" -ForegroundColor Cyan
    $oemInf = "C:\Windows\INF\oem2.inf"
    if (Test-Path $oemInf) {
        $matches = Select-String -Path $oemInf -Pattern "VEN_1414|DEV_008E|HyperV|Hyper-V" -CaseSensitive:$false
        if ($matches) {
            $matches | ForEach-Object { Write-Host $_.Line }
        } else {
            Write-Host "  No VEN_1414/DEV_008E entries found in oem2.inf - driver cannot bind to GPU-P device!" -ForegroundColor Red
        }
    } else {
        Write-Host "oem2.inf not found" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "=== Staged driver package info ===" -ForegroundColor Cyan
    pnputil /enum-drivers 2>&1 | Out-String | Select-String -Pattern "oem2" -Context 0,8

    Write-Host ""
    Write-Host "=== Try force scan ===" -ForegroundColor Cyan
    pnputil /scan-devices 2>&1
}
