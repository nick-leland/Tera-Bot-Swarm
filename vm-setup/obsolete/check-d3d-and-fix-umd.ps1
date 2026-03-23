$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $newDSPath = 'C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_3210371373e48d7f'
    $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001'

    Write-Host "=== Current UMD registration ==="
    $p = Get-ItemProperty $classKey
    Write-Host "DriverDesc: $($p.DriverDesc)"
    Write-Host "UMD[0]: $(if ($p.UserModeDriverName) { $p.UserModeDriverName[0] } else { '(none)' })"

    Write-Host "=== Updating UMD to new DriverStore ==="
    $umdPath = Join-Path $newDSPath 'nvldumdx.dll'
    if (Test-Path $umdPath) {
        $umdArr = @($umdPath, $umdPath, $umdPath, $umdPath)
        Set-ItemProperty -Path $classKey -Name 'UserModeDriverName' -Value $umdArr -Type MultiString
        Write-Host "Updated UMD to: $umdPath"
    } else {
        Write-Host "WARN: nvldumdx.dll not found at new path, keeping old UMD"
    }

    Write-Host "=== D3D11 test on GPU-P adapter ==="
    # Quick GPU utilization baseline
    $gpu3d = (Get-Counter '\GPU Engine(*engtype_3d*)\Utilization Percentage' -ErrorAction SilentlyContinue)
    $baseline = if ($gpu3d) { ($gpu3d.CounterSamples | Measure-Object CookedValue -Average).Average } else { 'N/A' }
    Write-Host "GPU 3D utilization (idle): $baseline %"

    Write-Host "=== DXGI adapter enumeration via dxdiag ==="
    $dxout = 'C:\Windows\Temp\dxdiag_out.txt'
    Start-Process dxdiag -ArgumentList "/t $dxout" -Wait -ErrorAction SilentlyContinue
    if (Test-Path $dxout) {
        Get-Content $dxout | Select-String 'Card name|Driver Version|WDDM|Feature Level|Display' | Select-Object -First 20 |
            ForEach-Object { $_.Line.Trim() }
        Remove-Item $dxout -ErrorAction SilentlyContinue
    }

    Write-Host "=== GPU engines available ==="
    $engines = (Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction SilentlyContinue)
    if ($engines) {
        $engines.CounterSamples | Select-Object -ExpandProperty InstanceName |
            ForEach-Object { ($_ -split '_')[-1] } | Sort-Object -Unique
    }

    Write-Host "=== Parsec running? ==="
    Get-Process parsecd -ErrorAction SilentlyContinue | Select-Object Name, Id, CPU | Format-List
}
