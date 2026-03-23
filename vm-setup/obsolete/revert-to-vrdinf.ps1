$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001'
    $hostStore = 'C:\Windows\System32\HostDriverStore\FileRepository\nv_dispi.inf_amd64_6d8eaa80a18aada4'
    $umdPath   = Join-Path $hostStore 'nvldumdx.dll'

    Write-Host "=== Removing oem4.inf (patched NVIDIA INF) from device ==="
    $result = pnputil /delete-driver oem4.inf /uninstall /force 2>&1
    Write-Host $result
    Start-Sleep -Seconds 5

    Write-Host ""
    Write-Host "=== Current device driver after removal ==="
    $dev = Get-PnpDevice | Where-Object { $_.InstanceId -like '*VEN_1414*' } | Select-Object -First 1
    $props = Get-PnpDeviceProperty -InputObject $dev -EA SilentlyContinue
    Write-Host "FriendlyName : $($dev.FriendlyName)"
    Write-Host "Status       : $($dev.Status)"
    Write-Host "InfPath      : $(($props | Where-Object KeyName -eq 'DEVPKEY_Device_DriverInfPath').Data)"
    Write-Host "Service      : $(($props | Where-Object KeyName -eq 'DEVPKEY_Device_Service').Data)"

    Write-Host ""
    Write-Host "=== Re-applying UMD override to class key ==="
    if (Test-Path $umdPath) {
        $umdArr = @($umdPath, $umdPath, $umdPath, $umdPath)
        Set-ItemProperty -Path $classKey -Name 'UserModeDriverName' -Value $umdArr -Type MultiString
        Write-Host "UMD set to: $umdPath"
    } else {
        Write-Host "ERROR: $umdPath not found"
    }

    Write-Host ""
    Write-Host "=== Class key after fix ==="
    $p = Get-ItemProperty $classKey
    Write-Host "DriverDesc   : $($p.DriverDesc)"
    Write-Host "DriverVersion: $($p.DriverVersion)"
    Write-Host "InfPath      : $($p.InfPath)"
    Write-Host "UMD[0]       : $(($p.UserModeDriverName)[0])"

    Write-Host ""
    Write-Host "Rebooting..."
    Restart-Computer -Force
}

Write-Host "Waiting for VM..."
Start-Sleep -Seconds 25
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 10
    try {
        $r = Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { 'ok' } -ErrorAction Stop
        if ($r -eq 'ok') { Write-Host "VM online ($($i*10+25)s)"; break }
    } catch { Write-Host "  Waiting... ($($i*10+25)s)" }
}

Start-Sleep -Seconds 5

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001'
    Write-Host "=== Post-reboot state ==="
    $dev = Get-PnpDevice | Where-Object { $_.InstanceId -like '*VEN_1414*' } | Select-Object -First 1
    $props = Get-PnpDeviceProperty -InputObject $dev -EA SilentlyContinue
    Write-Host "FriendlyName : $($dev.FriendlyName)"
    Write-Host "Status       : $($dev.Status)"
    Write-Host "Problem      : $($dev.Problem)"
    Write-Host "InfPath      : $(($props | Where-Object KeyName -eq 'DEVPKEY_Device_DriverInfPath').Data)"
    Write-Host "Service      : $(($props | Where-Object KeyName -eq 'DEVPKEY_Device_Service').Data)"
    $p = Get-ItemProperty $classKey -EA SilentlyContinue
    Write-Host "DriverDesc   : $($p.DriverDesc)"
    Write-Host "UMD[0]       : $(($p.UserModeDriverName)[0])"

    Write-Host ""
    Write-Host "=== GPU engine counter ==="
    $c = Get-Counter '\GPU Engine(*)\Utilization Percentage' -EA SilentlyContinue
    if ($c) { $c.CounterSamples | Select-Object -ExpandProperty InstanceName | ForEach-Object { ($_ -split '_')[-1] } | Sort-Object -Unique }
    else { Write-Host "(no counters)" }
}
