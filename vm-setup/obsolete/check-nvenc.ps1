$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host '=== All GPU engine types ==='
    $allCounters = Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction SilentlyContinue
    if ($allCounters) {
        $allCounters.CounterSamples | ForEach-Object { $_.Path } |
            ForEach-Object { if ($_ -match 'engtype_(\w+)') { $Matches[1] } } |
            Sort-Object -Unique
    }

    Write-Host '=== All GPU counter categories ==='
    $allCounters2 = Get-Counter '\GPU Engine(*)\*' -ErrorAction SilentlyContinue
    if ($allCounters2) {
        $allCounters2.CounterSamples | ForEach-Object { $_.Path } |
            ForEach-Object { if ($_ -match 'engtype_(\w+)') { $Matches[1] } } |
            Sort-Object -Unique
    }

    Write-Host '=== Check nvEncodeAPI64.dll is loadable ==='
    try {
        $asm = [System.Reflection.Assembly]::LoadFile('C:\Windows\System32\nvEncodeAPI64.dll')
        Write-Host 'nvEncodeAPI64.dll: loaded as .NET assembly'
    } catch {
        Write-Host "nvEncodeAPI64.dll load attempt: $($_.Exception.Message)"
    }

    # Check if video encode counter exists specifically
    Write-Host '=== Video encode engine counters ==='
    if ($allCounters) {
        $allCounters.CounterSamples | Where-Object { $_.Path -like '*video_encode*' -or $_.Path -like '*encode*' } |
            Format-Table Path, CookedValue -AutoSize
    }

    Write-Host '=== DXGI adapters via WMI ==='
    Get-WmiObject Win32_VideoController | Select-Object Name, AdapterCompatibility, DriverVersion | Format-List
}
