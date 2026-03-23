$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Verify config.json content
    Write-Host '=== config.json ==='
    $bytes = [System.IO.File]::ReadAllBytes('C:\Users\bot\AppData\Roaming\Parsec\config.json')
    Write-Host "First byte: $($bytes[0]) (should be 91 for [ )"
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\config.json'

    # Verify Parsec service is Automatic
    Write-Host '=== Parsec service ==='
    Get-Service 'Parsec' | Select-Object Name, Status, StartType

    # Ensure Run key is clean (no manual parsecd)
    Remove-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'Parsec' -ErrorAction SilentlyContinue
    Remove-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'Parsec.App.0' -ErrorAction SilentlyContinue
    Write-Host '=== Run key (should only have OneDrive) ==='
    Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'

    # Reboot
    Write-Host 'Rebooting...'
    Restart-Computer -Force
}
