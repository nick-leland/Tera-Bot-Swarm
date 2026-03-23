$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Write-Host 'Rebooting VM...'
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Restart-Computer -Force
} -ErrorAction SilentlyContinue

Start-Sleep -Seconds 15
Write-Host 'Waiting for VM to come back (up to 3 minutes)...'

for ($i = 0; $i -lt 18; $i++) {
    Start-Sleep -Seconds 10
    try {
        $r = Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { 'ok' } -ErrorAction Stop
        if ($r -eq 'ok') { Write-Host 'VM is back online.'; break }
    } catch {
        Write-Host "  Waiting... ($($i*10+10)s)"
    }
}

Write-Host 'Waiting 60 more seconds for boot tasks + auto-logon + Parsec...'
Start-Sleep -Seconds 60

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host '=== NVIDIA status ==='
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' } | Select-Object Status, FriendlyName

    Write-Host '=== GPU adapter UMD in registry ==='
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($p.DriverDesc) {
                $umd = if ($p.UserModeDriverName) { $p.UserModeDriverName[0] } else { '(none)' }
                Write-Host "  $($p.DriverDesc): UMD=$umd"
            }
        }

    Write-Host '=== nvidia-dll-copy.log ==='
    Get-Content 'C:\Windows\Temp\nvidia-dll-copy.log' -ErrorAction SilentlyContinue

    Write-Host '=== nvidia-fix.log ==='
    Get-Content 'C:\Windows\Temp\nvidia-fix.log' -ErrorAction SilentlyContinue

    Write-Host '=== dxdiag (WDDM check) ==='
    $out = "$env:TEMP\dx3.txt"
    Start-Process dxdiag -ArgumentList "/t $out" -Wait -WindowStyle Hidden
    Start-Sleep -Seconds 6
    if (Test-Path $out) {
        $content = Get-Content $out
        $content | Select-String 'Card name|Driver Model|WDDM|DDI Version' | ForEach-Object { Write-Host "  $($_.Line.Trim())" }
        Remove-Item $out -Force
    }

    Write-Host '=== Parsec processes ==='
    Get-WmiObject Win32_Process | Where-Object { $_.Name -like 'parsec*' } |
        Select-Object Name, ProcessId, SessionId | Format-Table -AutoSize
}
