$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Show current config
    Write-Host '=== Current config.json ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\config.json'

    # Check if bot is actually admin
    Write-Host '=== bot groups ==='
    whoami /groups | findstr /i admin

    # Show current Run key
    Write-Host '=== Run key ==='
    Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' | Select-Object Parsec*, OneDrive

    # Fix config: standalone mode, preserve block hash, remove release17 channel
    Stop-Process -Name parsecd -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $obj = @(
        'See https://parsec.app/config for documentation and example. JSON must be valid before saving or file be will be erased.',
        [ordered]@{
            app_block_hash = [ordered]@{ value = 'b4e1daaee72eb9ea621918eaa4293a50bcf9c4d71fb545325b7dcd8b0e858f34' }
            app_run_level  = [ordered]@{ value = 0 }
        }
    )
    $json = $obj | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText('C:\Users\bot\AppData\Roaming\Parsec\config.json', $json, $utf8NoBom)
    Write-Host 'Config updated: standalone (0) + block hash, no release17 channel'

    Write-Host '=== New config.json ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\config.json'

    # Reboot
    Write-Host 'Rebooting...'
    Restart-Computer -Force
}
