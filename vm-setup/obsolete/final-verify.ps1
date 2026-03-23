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
    # Wait for parsecd to start (30s delay from logon)
    Write-Host 'Waiting up to 45s for parsecd to start...'
    for ($i = 0; $i -lt 9; $i++) {
        $p = Get-Process parsecd -ErrorAction SilentlyContinue
        if ($p) { Write-Host "parsecd started (PID: $($p.Id))"; break }
        Start-Sleep -Seconds 5
    }

    Write-Host '=== NVIDIA status ==='
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' } | Select-Object Status, FriendlyName

    Write-Host '=== nvidia-fix.log (last 12 lines) ==='
    Get-Content 'C:\Windows\Temp\nvidia-fix.log' -ErrorAction SilentlyContinue | Select-Object -Last 12

    Write-Host '=== parsecd processes ==='
    Get-WmiObject Win32_Process | Where-Object { $_.Name -eq 'parsecd.exe' } |
        Select-Object ProcessId, SessionId, CommandLine | Format-List

    Write-Host '=== Parsec log (last 25 lines) ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\log.txt' -ErrorAction SilentlyContinue | Select-Object -Last 25

    Write-Host '=== Display adapters ==='
    Get-PnpDevice | Where-Object { $_.Class -eq 'Display' } | Select-Object Status, FriendlyName
}
