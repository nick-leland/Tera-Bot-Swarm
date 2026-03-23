Start-Sleep -Seconds 60
$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
for ($i = 0; $i -lt 15; $i++) {
    try {
        $r = Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { 'ok' } -ErrorAction Stop
        if ($r -eq 'ok') { Write-Host 'VM is up'; break }
    } catch {}
    Write-Host "Waiting... $i"
    Start-Sleep -Seconds 10
}
