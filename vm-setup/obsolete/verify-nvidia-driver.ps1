$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Write-Host 'Waiting for VM...'
for ($i = 0; $i -lt 20; $i++) {
    try {
        $r = Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { 'ok' } -ErrorAction Stop
        if ($r -eq 'ok') { Write-Host 'VM is up'; break }
    } catch { Write-Host "Attempt $i..."; Start-Sleep -Seconds 10 }
}

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host '=== NVIDIA PnP status ==='
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' } | Select-Object Status, FriendlyName

    Write-Host '=== What driver is bound to NVIDIA GPU-P ==='
    Get-WmiObject Win32_PnPSignedDriver | Where-Object { $_.DeviceName -like '*NVIDIA GeForce*' } |
        Select-Object DeviceName, DriverVersion, DriverProviderName, InfName | Format-List

    Write-Host '=== HostDriverStore NVIDIA folders ==='
    Get-ChildItem 'C:\Windows\System32\HostDriverStore\FileRepository' -Filter 'nv_dispi*' -Directory -ErrorAction SilentlyContinue |
        Select-Object Name, LastWriteTime

    Write-Host '=== NVIDIA DLLs in System32 ==='
    @('nvwgf2umx.dll', 'nvapi64.dll', 'nvEncodeAPI64.dll', 'nvcuda.dll', 'nvlddmkm.sys') | ForEach-Object {
        $p = "C:\Windows\System32\$_"
        if (Test-Path $p) {
            $sz = [math]::Round((Get-Item $p).Length / 1MB, 1)
            Write-Host "  EXISTS: $_ ($sz MB)"
        } else { Write-Host "  MISSING: $_" }
    }

    Write-Host '=== GPU performance counters ==='
    $gpuCounters = Get-Counter '\GPU Engine(*engines_0*)\Utilization Percentage' -ErrorAction SilentlyContinue
    if ($gpuCounters) {
        $gpuCounters.CounterSamples | Select-Object -First 5 Path | Format-Table -AutoSize
    } else {
        $allCounters = Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction SilentlyContinue
        if ($allCounters) {
            Write-Host 'GPU counters present (GPU visible to Task Manager)'
            $allCounters.CounterSamples | Select-Object -First 3 | Format-Table Path, CookedValue
        } else { Write-Host 'No GPU engine counters' }
    }

    Write-Host '=== Parsec log (last 15 lines) ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\log.txt' -ErrorAction SilentlyContinue | Select-Object -Last 15
}
