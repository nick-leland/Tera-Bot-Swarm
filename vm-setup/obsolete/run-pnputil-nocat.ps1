$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $tmpDir = 'C:\Windows\Temp\nvidia-drv-new'
    $infPath = Join-Path $tmpDir 'nv_dispi.inf'
    $catPath = Join-Path $tmpDir 'NV_DISP.CAT'

    Write-Host "=== Removing NV_DISP.CAT ==="
    if (Test-Path $catPath) {
        Remove-Item $catPath -Force
        Write-Host "Removed NV_DISP.CAT"
    }

    Write-Host "=== testsigning / nointegritychecks status ==="
    bcdedit /enum '{current}' 2>&1 | Select-String 'testsigning|nointegrity' | ForEach-Object { Write-Host "  $_" }

    Write-Host "=== pnputil /add-driver /install (no catalog) ==="
    $result = pnputil /add-driver $infPath /install 2>&1
    Write-Host $result

    Write-Host "=== pnputil /add-driver (staging only, no install) ==="
    $result2 = pnputil /add-driver $infPath 2>&1
    Write-Host $result2

    Write-Host "=== NVIDIA device status ==="
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA*' -or $_.InstanceId -like '*VEN_1414*' } |
        Select-Object Status, FriendlyName, InstanceId | Format-List
}
