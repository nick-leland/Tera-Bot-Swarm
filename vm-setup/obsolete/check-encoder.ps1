$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host '=== NVIDIA PnP status ==='
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA*' } | Select-Object Status, FriendlyName

    Write-Host '=== GPU performance counters ==='
    $allCounters = Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction SilentlyContinue
    if ($allCounters) {
        Write-Host 'GPU counters present'
        $allCounters.CounterSamples | Select-Object -First 5 | Format-Table Path, CookedValue -AutoSize
    } else {
        Write-Host 'No GPU engine counters found'
    }

    Write-Host '=== log_cl.txt (last 40 lines) ==='
    $logCl = Get-ChildItem 'C:\Users\bot\AppData\Roaming\Parsec\' -Filter 'log_cl*' -ErrorAction SilentlyContinue
    foreach ($f in $logCl) {
        Write-Host "--- $($f.Name) ---"
        Get-Content $f.FullName -ErrorAction SilentlyContinue | Select-Object -Last 40
    }

    Write-Host '=== Parsec log.txt (last 15 lines) ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\log.txt' -ErrorAction SilentlyContinue | Select-Object -Last 15

    Write-Host '=== Display adapters ==='
    Get-PnpDevice | Where-Object { $_.Class -eq 'Display' } | Select-Object Status, FriendlyName
}
