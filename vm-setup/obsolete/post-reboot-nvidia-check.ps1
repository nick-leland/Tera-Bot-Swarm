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
    Write-Host '=== NVIDIA status ==='
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' } | Select-Object Status, FriendlyName

    Write-Host '=== HostDriverStore NVIDIA folders ==='
    Get-ChildItem 'C:\Windows\System32\HostDriverStore\FileRepository' -Filter 'nv_dispi*' -Directory -ErrorAction SilentlyContinue |
        Select-Object Name, LastWriteTime

    Write-Host '=== nvidia-fix.log (last 10 lines) ==='
    Get-Content 'C:\Windows\Temp\nvidia-fix.log' -ErrorAction SilentlyContinue | Select-Object -Last 10

    Write-Host '=== Parsec log (last 20 lines) ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\log.txt' -ErrorAction SilentlyContinue | Select-Object -Last 20
}
