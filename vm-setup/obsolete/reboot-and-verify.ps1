$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Write-Host "Rebooting VM..."
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Restart-Computer -Force
} -ErrorAction SilentlyContinue

Write-Host "Waiting for VM to come back (up to 3 min)..."
Start-Sleep -Seconds 20
for ($i = 0; $i -lt 22; $i++) {
    Start-Sleep -Seconds 10
    try {
        $r = Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { 'ok' } -ErrorAction Stop
        if ($r -eq 'ok') { Write-Host "VM is back online (after ~$($i*10+20)s)."; break }
    } catch {
        Write-Host "  Waiting... ($($i*10+20)s)"
    }
}

Start-Sleep -Seconds 15

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host "=== VEN_1414 device after reboot ==="
    $dev = Get-PnpDevice | Where-Object { $_.InstanceId -like '*VEN_1414*' } | Select-Object -First 1
    Write-Host "FriendlyName : $($dev.FriendlyName)"
    Write-Host "Status       : $($dev.Status)"

    $props = Get-PnpDeviceProperty -InputObject $dev -ErrorAction SilentlyContinue
    $service   = ($props | Where-Object KeyName -eq 'DEVPKEY_Device_Service').Data
    $infPath   = ($props | Where-Object KeyName -eq 'DEVPKEY_Device_DriverInfPath').Data
    $drvVer    = ($props | Where-Object KeyName -eq 'DEVPKEY_Device_DriverVersion').Data
    $drvDesc   = ($props | Where-Object KeyName -eq 'DEVPKEY_Device_DriverDesc').Data
    $stack     = ($props | Where-Object KeyName -eq 'DEVPKEY_Device_Stack').Data
    Write-Host "Service      : $service"
    Write-Host "INF          : $infPath"
    Write-Host "Version      : $drvVer"
    Write-Host "DriverDesc   : $drvDesc"
    Write-Host "Stack        : $stack"

    Write-Host "=== nvlddmkm service ==="
    Get-Service nvlddmkm -ErrorAction SilentlyContinue | Select-Object Name, Status, StartType | Format-List
    sc.exe qc nvlddmkm 2>&1

    Write-Host "=== VirtualRender service ==="
    Get-Service VirtualRender -ErrorAction SilentlyContinue | Select-Object Name, Status, StartType | Format-List

    Write-Host "=== GPU engine types ==="
    $counters = Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction SilentlyContinue
    if ($counters) {
        $counters.CounterSamples | Select-Object -ExpandProperty InstanceName |
            ForEach-Object { ($_ -split '_')[-1] } | Sort-Object -Unique
    } else {
        Write-Host "(no GPU counters)"
    }

    Write-Host "=== GPU adapter registry ==="
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($p.DriverDesc) {
                $umd = if ($p.UserModeDriverName) { $p.UserModeDriverName[0] } else { '(none)' }
                Write-Host "  $($p.DriverDesc) | Svc: $($p.ImagePath) | UMD: $umd | Ver: $($p.DriverVersion)"
            }
        }
}
