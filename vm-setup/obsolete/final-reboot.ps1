$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Final state check before reboot
    Write-Host '=== Config ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\config.json'
    Write-Host '=== Parsec service StartType ==='
    Get-Service 'Parsec' | Select-Object Name, StartType
    Write-Host 'Rebooting...'
    Restart-Computer -Force
}
