$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host '=== NVIDIA status ==='
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA*' } | Select-Object Status, FriendlyName

    Write-Host '=== Display adapters ==='
    Get-PnpDevice | Where-Object { $_.Class -eq 'Display' } | Select-Object Status, FriendlyName

    Write-Host '=== NVIDIA DLLs ==='
    foreach ($f in @('nvwgf2umx.dll', 'nvapi64.dll', 'nvEncodeAPI64.dll', 'nvcuda.dll', 'nvml.dll')) {
        $p = "C:\Windows\System32\$f"
        if (Test-Path $p) {
            $sz = [math]::Round((Get-Item $p).Length / 1MB, 1)
            Write-Host "  OK: $f ($sz MB)"
        } else { Write-Host "  MISSING: $f" }
    }

    Write-Host '=== Scheduled tasks ==='
    Get-ScheduledTask | Where-Object { $_.TaskName -in @('Fix-NVIDIA-GPU','Copy-NVIDIA-DLLs','StartParsecAtLogon') } |
        Select-Object TaskName, State | Format-Table -AutoSize

    Write-Host '=== VirtualRender service ==='
    $svc = Get-Service 'VirtualRender' -ErrorAction SilentlyContinue
    Write-Host "  Status: $($svc.Status), StartType: $($svc.StartType)"

    Write-Host '=== Parsec processes ==='
    Get-WmiObject Win32_Process | Where-Object { $_.Name -like 'parsec*' } |
        Select-Object Name, ProcessId, SessionId | Format-Table -AutoSize

    Write-Host '=== GPU engine types ==='
    $counters = Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction SilentlyContinue
    if ($counters) {
        $counters.CounterSamples | ForEach-Object { $_.Path } |
            ForEach-Object { if ($_ -match 'engtype_(\w+)') { $Matches[1] } } |
            Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
    }

    Write-Host '=== AutoAdminLogon ==='
    $al = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    Write-Host "  AutoAdminLogon=$($al.AutoAdminLogon), User=$($al.DefaultUserName)"
}
