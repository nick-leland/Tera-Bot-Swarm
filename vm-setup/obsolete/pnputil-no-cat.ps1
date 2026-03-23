$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $tmpDir = 'C:\Windows\Temp\nvidia-drv'
    $infPath = Join-Path $tmpDir 'nv_dispi.inf'

    Write-Host '=== Removing NV_DISP.CAT to try unsigned install ==='
    $catPath = Join-Path $tmpDir 'NV_DISP.CAT'
    if (Test-Path $catPath) {
        Remove-Item $catPath -Force
        Write-Host 'Removed NV_DISP.CAT'
    }

    Write-Host '=== pnputil /add-driver (no catalog) ==='
    $result = pnputil /add-driver $infPath /install 2>&1
    Write-Host $result

    Write-Host '=== Try with just adding (not installing) first ==='
    $result2 = pnputil /add-driver $infPath 2>&1
    Write-Host $result2

    # Alternative: try DevCon approach if available
    Write-Host '=== Check for devcon.exe ==='
    $devcon = Get-ChildItem 'C:\Windows\System32\devcon.exe', 'C:\Tools\devcon.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($devcon) {
        Write-Host "devcon found: $($devcon.FullName)"
        & $devcon.FullName update $infPath 'PCI\VEN_1414&DEV_008E'
    } else {
        Write-Host 'devcon.exe not found'
    }

    # Show what pnputil thinks about the current VEN_1414 device
    Write-Host '=== pnputil enum VEN_1414 device ==='
    pnputil /enum-devices /instanceid '*VEN_1414*' 2>&1
}
