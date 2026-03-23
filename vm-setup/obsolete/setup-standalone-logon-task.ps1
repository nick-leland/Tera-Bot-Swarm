$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Stop and disable Parsec service
    Stop-Service 'Parsec' -Force -ErrorAction SilentlyContinue
    Stop-Process -Name parsecd -Force -ErrorAction SilentlyContinue
    Set-Service 'Parsec' -StartupType Disabled
    Start-Sleep -Seconds 2

    # Set standalone mode config
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
    Write-Host 'Config: standalone (0) + block hash'

    # Write launch script with delay
    $launchScript = "Start-Sleep -Seconds 10`nStart-Process 'C:\Program Files\Parsec\parsecd.exe'"
    [System.IO.File]::WriteAllText('C:\Users\bot\launch-parsec.ps1', $launchScript, [System.Text.Encoding]::UTF8)
    Write-Host 'launch-parsec.ps1 written'

    # Create scheduled task at logon: Interactive, RunLevel Highest (admin), 10s delay via launcher
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Users\bot\launch-parsec.ps1'
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User 'bot'
    $principal = New-ScheduledTaskPrincipal -UserId 'bot' -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 24) -AllowStartIfOnBatteries

    Unregister-ScheduledTask -TaskName 'StartParsecAtLogon' -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName 'StartParsecAtLogon' -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
    Write-Host 'Scheduled task created: StartParsecAtLogon (logon, Interactive, Highest, 10s delay)'

    # Verify task
    Get-ScheduledTask -TaskName 'StartParsecAtLogon' | Select-Object TaskName, State

    Write-Host 'Rebooting...'
    Restart-Computer -Force
}
