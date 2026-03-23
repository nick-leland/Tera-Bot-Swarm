$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

# Wait for VM to come back if it rebooted
for ($i = 0; $i -lt 18; $i++) {
    try {
        $r = Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { 'ok' } -ErrorAction Stop
        if ($r -eq 'ok') { Write-Host "VM is online."; break }
    } catch {
        Write-Host "Waiting... ($($i*10)s) - $($_.Exception.Message)"
        Start-Sleep -Seconds 10
    }
}

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host "=== NVIDIA device status ==="
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA*' -or $_.InstanceId -like '*VEN_1414*' } |
        Select-Object Status, FriendlyName, InstanceId, Class | Format-List

    Write-Host "=== Display adapters ==="
    Get-PnpDevice | Where-Object { $_.Class -eq 'Display' } |
        Select-Object Status, FriendlyName, InstanceId | Format-List

    Write-Host "=== GPU adapter registry ==="
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($p.DriverDesc) {
                $umd = if ($p.UserModeDriverName) { $p.UserModeDriverName[0] } else { '(none)' }
                Write-Host "  $($p.DriverDesc) | KMD: $($p.InstalledDisplayDrivers) | UMD: $umd | Ver: $($p.DriverVersion)"
            }
        }

    Write-Host "=== GPU engine counters ==="
    (Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction SilentlyContinue).CounterSamples |
        Where-Object { $_.InstanceName -notlike '*_3d*' -and $_.CookedValue -ge 0 } |
        Select-Object InstanceName, CookedValue | Format-Table -AutoSize

    Write-Host "=== GPU engine types available ==="
    (Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction SilentlyContinue).CounterSamples |
        Select-Object -ExpandProperty InstanceName | ForEach-Object { ($_ -split '_')[-1] } |
        Sort-Object -Unique

    Write-Host "=== DriverStore - NVIDIA entries ==="
    Get-ChildItem 'C:\Windows\System32\DriverStore\FileRepository' |
        Where-Object { $_.Name -like 'nv_*' } |
        Select-Object Name, LastWriteTime | Format-Table -AutoSize
}
