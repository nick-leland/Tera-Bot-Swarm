$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Write-Host "=== HOST: GPU-P proxy processes ==="
$hostGpu = Get-Counter '\GPU Engine(*)\Utilization Percentage' -EA SilentlyContinue
if ($hostGpu) {
    $hostGpu.CounterSamples | Where-Object CookedValue -gt 0.05 |
        Select-Object InstanceName, @{N='Pct';E={[math]::Round($_.CookedValue,2)}} |
        Sort-Object Pct -Descending | Format-Table -AutoSize
}

Write-Host "=== HOST: PIDs with GPU activity ==="
$hostGpu.CounterSamples | Where-Object CookedValue -gt 0.05 | ForEach-Object {
    if ($_.InstanceName -match 'pid_(\d+)') {
        $pid2 = [int]$Matches[1]
        $proc = Get-Process -Id $pid2 -EA SilentlyContinue
        if ($proc) { Write-Host "  PID $pid2 = $($proc.ProcessName) ($($proc.MainWindowTitle))" }
        else { Write-Host "  PID $pid2 = (no process)" }
    }
} | Sort-Object -Unique

Write-Host ""
Write-Host "=== VM: TERA adapter + utilization ==="
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host "TERA process:"
    $tera = Get-Process TERA -EA SilentlyContinue
    if ($tera) {
        Write-Host "  PID=$($tera.Id) CPU=$([math]::Round($tera.CPU,1))s WorkingSet=$([math]::Round($tera.WorkingSet64/1MB,0))MB"
        Write-Host "  Handles=$($tera.HandleCount)"
    } else {
        Write-Host "  NOT RUNNING"
    }

    Write-Host ""
    Write-Host "VM GPU Engine utilization (all adapters):"
    $vmGpu = Get-Counter '\GPU Engine(*)\Utilization Percentage' -EA SilentlyContinue
    if ($vmGpu) {
        $vmGpu.CounterSamples | Where-Object CookedValue -gt 0.0 |
            Select-Object @{N='Instance';E={$_.InstanceName}},
                          @{N='Pct';E={[math]::Round($_.CookedValue,3)}} |
            Sort-Object Pct -Descending | Format-Table -AutoSize
    } else {
        Write-Host "(no GPU counters)"
    }

    Write-Host ""
    Write-Host "VM GPU adapters (LUIDs):"
    $vmGpu.CounterSamples | ForEach-Object {
        if ($_.InstanceName -match 'luid_0x([0-9a-f]+)_0x([0-9a-f]+)') {
            "$($Matches[1])_$($Matches[2])"
        }
    } | Sort-Object -Unique | ForEach-Object { Write-Host "  LUID: $_" }

    Write-Host ""
    Write-Host "VM CPU usage (top processes):"
    Get-Process | Sort-Object CPU -Descending | Select-Object -First 8 |
        Select-Object Name, Id, @{N='CPU_s';E={[math]::Round($_.CPU,1)}},
                      @{N='WS_MB';E={[math]::Round($_.WorkingSet64/1MB,0)}} |
        Format-Table -AutoSize
} -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== HOST: svchost videoencode (Hyper-V GPU-P proxy) ==="
$svcs = Get-Process svchost | Select-Object Id, CPU | Sort-Object CPU -Descending | Select-Object -First 5
$svcs | Format-Table -AutoSize
