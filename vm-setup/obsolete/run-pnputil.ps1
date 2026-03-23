$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $tmpDir = 'C:\Windows\Temp\nvidia-drv-new'
    $infPath = Join-Path $tmpDir 'nv_dispi.inf'

    Write-Host "=== Files in temp dir ==="
    Write-Host ((Get-ChildItem $tmpDir).Count)

    Write-Host "=== Key files ==="
    foreach ($f in @('nv_dispi.inf', 'NV_DISP.CAT', 'nvlddmkm.sys', 'nvwgf2umx.dll', 'nvldumdx.dll')) {
        $p = Join-Path $tmpDir $f
        if (Test-Path $p) {
            $sz = [math]::Round((Get-Item $p).Length / 1MB, 2)
            Write-Host "  OK: $f ($sz MB)"
        } else { Write-Host "  MISSING: $f" }
    }

    Write-Host "=== VEN_1414 in patched INF ==="
    Get-Content $infPath | Select-String 'VEN_1414' | ForEach-Object { Write-Host "  $_" }

    Write-Host "=== pnputil /add-driver /install ==="
    $result = pnputil /add-driver $infPath /install 2>&1
    Write-Host $result

    Write-Host "=== NVIDIA device status ==="
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA*' -or $_.InstanceId -like '*VEN_1414*' } |
        Select-Object Status, FriendlyName, InstanceId | Format-List
}
