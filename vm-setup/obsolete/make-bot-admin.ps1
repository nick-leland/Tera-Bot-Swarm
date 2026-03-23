$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Add bot to Administrators group
    $result = net localgroup Administrators bot /add 2>&1
    Write-Host "Add to Administrators: $result"

    # Verify
    $groups = net localgroup Administrators 2>&1
    Write-Host "Administrators members:"
    $groups | Where-Object { $_ -match 'bot' }

    # Kill parsecd so it restarts with new token on next logon
    Stop-Process -Name parsecd -Force -ErrorAction SilentlyContinue
    Write-Host 'Killed parsecd - will restart at next logon with admin token'
}
