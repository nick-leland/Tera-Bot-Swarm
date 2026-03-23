$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

# Wait for VM to be reachable
Write-Host 'Waiting for VM...'
for ($i = 0; $i -lt 20; $i++) {
    try {
        $r = Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { 'ok' } -ErrorAction Stop
        if ($r -eq 'ok') { Write-Host 'VM is up'; break }
    } catch { Write-Host "Attempt $i failed, retrying..."; Start-Sleep -Seconds 10 }
}

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Remove duplicate Parsec.App.0 Run key
    $runKey = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    $existing = Get-ItemProperty $runKey -Name 'Parsec.App.0' -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-ItemProperty $runKey -Name 'Parsec.App.0' -ErrorAction SilentlyContinue
        Write-Host 'Removed Parsec.App.0 from Run key'
    } else {
        Write-Host 'Parsec.App.0 not found in Run key (already gone)'
    }

    Write-Host '=== Run key ==='
    Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' | Select-Object Parsec*, OneDrive

    Write-Host '=== VirtualRender service ==='
    Get-Service -Name 'VirtualRender' -ErrorAction SilentlyContinue | Select-Object Name, Status, StartType

    Write-Host '=== NVIDIA status ==='
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA*' } | Select-Object Status, FriendlyName

    Write-Host '=== parsecd processes ==='
    Get-WmiObject Win32_Process | Where-Object { $_.Name -eq 'parsecd.exe' } |
        Select-Object ProcessId, SessionId, CommandLine | Format-List

    Write-Host '=== Parsec log (last 40 lines) ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\log.txt' -ErrorAction SilentlyContinue | Select-Object -Last 40
}
