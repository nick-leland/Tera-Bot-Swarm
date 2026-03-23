$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Write-Host "=== VM GPU state ==="
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001'
    $p = Get-ItemProperty $classKey -EA SilentlyContinue
    Write-Host "DriverDesc   : $($p.DriverDesc)"
    Write-Host "DriverVersion: $($p.DriverVersion)"
    Write-Host "InfPath      : $($p.InfPath)"
    Write-Host "UMD[0]       : $(if ($p.UserModeDriverName) { $p.UserModeDriverName[0] } else { '(none)' })"

    $dev = Get-PnpDevice | Where-Object { $_.InstanceId -like '*VEN_1414*' } | Select-Object -First 1
    $props = Get-PnpDeviceProperty -InputObject $dev -EA SilentlyContinue
    Write-Host "Service      : $(($props | Where-Object KeyName -eq 'DEVPKEY_Device_Service').Data)"
    Write-Host "Status       : $($dev.Status)"

    Write-Host ""
    Write-Host "=== DXGI adapter 0 (what TERA uses by default) ==="
    # Check which adapter is adapter 0 via GPU counter
    $counters = Get-Counter '\GPU Engine(*)\Utilization Percentage' -EA SilentlyContinue
    if ($counters) {
        $adapters = $counters.CounterSamples | ForEach-Object {
            if ($_.InstanceName -match 'luid_0x([0-9a-f]+)_0x([0-9a-f]+)') {
                [pscustomobject]@{
                    High = $Matches[1]
                    Low  = $Matches[2]
                    EngType = ($_.InstanceName -split '_')[-1]
                    InstanceName = $_.InstanceName
                }
            }
        } | Sort-Object High, Low -Unique | Select-Object -First 5
        $adapters | Format-Table
    }

    Write-Host ""
    Write-Host "=== TERA process running? ==="
    $tera = Get-Process -Name TERA -ErrorAction SilentlyContinue
    if ($tera) {
        Write-Host "TERA is running: PID=$($tera.Id), CPU=$($tera.CPU), WorkingSet=$([math]::Round($tera.WorkingSet64/1MB,1))MB"
    } else {
        Write-Host "TERA not currently running"
    }

    Write-Host ""
    Write-Host "=== Host D3DKMT adapter LUIDs (from GPU counters) ==="
    if ($counters) {
        $counters.CounterSamples | ForEach-Object {
            if ($_.InstanceName -match 'luid_0x([0-9a-f]+)_0x([0-9a-f]+)') {
                "$($Matches[1])_$($Matches[2])"
            }
        } | Sort-Object -Unique | ForEach-Object { Write-Host "  LUID: $_" }
    }
}

Write-Host ""
Write-Host "=== Host GPU utilization now ==="
$gpu = Get-Counter '\GPU Engine(*)\Utilization Percentage' -EA SilentlyContinue
if ($gpu) {
    $gpu.CounterSamples | Where-Object CookedValue -gt 0.1 |
        Select-Object InstanceName, CookedValue |
        Format-Table -AutoSize
} else {
    Write-Host "(no GPU counter on host)"
}
