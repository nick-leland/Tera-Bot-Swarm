$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $enumPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\VEN_1414&DEV_008E&SUBSYS_00000000&REV_00\5&59d1a3c&0&0'
    $drvStorePath = 'C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_3210371373e48d7f'
    $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001'

    Write-Host "=== Current Service value ==="
    $cur = (Get-ItemProperty $enumPath).Service
    Write-Host "Current: $cur"

    Write-Host "=== Setting Service = nvlddmkm ==="
    try {
        Set-ItemProperty -Path $enumPath -Name 'Service' -Value 'nvlddmkm' -Type String
        $new = (Get-ItemProperty $enumPath).Service
        Write-Host "Set to: $new"
    } catch {
        Write-Host "ERROR: $($_.Exception.Message)"
        # Try taking ownership first
        Write-Host "Trying reg.exe..."
        & reg.exe add "HKLM\SYSTEM\CurrentControlSet\Enum\PCI\VEN_1414&DEV_008E&SUBSYS_00000000&REV_00\5&59d1a3c&0&0" /v Service /t REG_SZ /d nvlddmkm /f 2>&1
    }

    Write-Host "=== Updating class key UMD path to new DriverStore ==="
    $umdPath = Join-Path $drvStorePath 'nvldumdx.dll'
    $umdArr = @($umdPath, $umdPath, $umdPath, $umdPath)
    Set-ItemProperty -Path $classKey -Name 'UserModeDriverName' -Value $umdArr -Type MultiString -ErrorAction SilentlyContinue
    Write-Host "UMD: $umdPath"

    Write-Host "=== Making nvlddmkm Start = 3 (Demand, correct for WDDM) ==="
    $nvSvc = 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm'
    Set-ItemProperty -Path $nvSvc -Name 'Start' -Value 3 -Type DWord -ErrorAction SilentlyContinue
    Write-Host "nvlddmkm Start: $((Get-ItemProperty $nvSvc).Start)"

    Write-Host "=== Final state ==="
    Write-Host "Device Service: $((Get-ItemProperty $enumPath).Service)"
    Write-Host "nvlddmkm ImagePath: $((Get-ItemProperty $nvSvc).ImagePath)"

    Write-Host ""
    Write-Host "Rebooting now..."
    Restart-Computer -Force
}

Write-Host "Waiting for VM to come back..."
Start-Sleep -Seconds 25
for ($i = 0; $i -lt 22; $i++) {
    Start-Sleep -Seconds 10
    try {
        $r = Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { 'ok' } -ErrorAction Stop
        if ($r -eq 'ok') { Write-Host "VM online (after ~$($i*10+25)s)."; break }
    } catch { Write-Host "  Waiting... ($($i*10+25)s)" }
}

Start-Sleep -Seconds 10

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host "=== VEN_1414 device after reboot ==="
    $dev = Get-PnpDevice | Where-Object { $_.InstanceId -like '*VEN_1414*' } | Select-Object -First 1
    $props = Get-PnpDeviceProperty -InputObject $dev -ErrorAction SilentlyContinue
    $service = ($props | Where-Object KeyName -eq 'DEVPKEY_Device_Service').Data
    $stack   = ($props | Where-Object KeyName -eq 'DEVPKEY_Device_Stack').Data
    $drvVer  = ($props | Where-Object KeyName -eq 'DEVPKEY_Device_DriverVersion').Data
    $drvDesc = ($props | Where-Object KeyName -eq 'DEVPKEY_Device_DriverDesc').Data
    Write-Host "FriendlyName : $($dev.FriendlyName)"
    Write-Host "Status       : $($dev.Status)"
    Write-Host "Service      : $service"
    Write-Host "Stack        : $stack"
    Write-Host "DriverDesc   : $drvDesc"
    Write-Host "DriverVersion: $drvVer"

    Write-Host "=== nvlddmkm service ==="
    Get-Service nvlddmkm -ErrorAction SilentlyContinue | Select-Object Name, Status | Format-List

    Write-Host "=== GPU engine types ==="
    $counters = Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction SilentlyContinue
    if ($counters) {
        $counters.CounterSamples | Select-Object -ExpandProperty InstanceName |
            ForEach-Object { ($_ -split '_')[-1] } | Sort-Object -Unique
    } else {
        Write-Host "(no GPU counters)"
    }

    Write-Host "=== Display adapters ==="
    Get-PnpDevice | Where-Object { $_.Class -eq 'Display' } |
        Select-Object Status, FriendlyName | Format-Table -AutoSize
}
