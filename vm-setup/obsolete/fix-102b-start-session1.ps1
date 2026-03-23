$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Kill all parsecd
    Stop-Process -Name parsecd -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Delete 102b DLL
    Remove-Item 'C:\Users\bot\AppData\Roaming\Parsec\parsecd-150-102b.dll' -Force -ErrorAction SilentlyContinue
    Write-Host "102b deleted: $(-not (Test-Path 'C:\Users\bot\AppData\Roaming\Parsec\parsecd-150-102b.dll'))"

    # Write config with block hash (prevents 102b re-download) + standalone
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
    Write-Host 'config.json: standalone + block hash'

    # Start parsecd in Session 1 via scheduled task (runs as bot interactively)
    $action = New-ScheduledTaskAction -Execute 'C:\Program Files\Parsec\parsecd.exe'
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5)
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 24)
    $principal = New-ScheduledTaskPrincipal -UserId 'bot' -LogonType Interactive

    Unregister-ScheduledTask -TaskName 'StartParsec' -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName 'StartParsec' -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
    Start-ScheduledTask -TaskName 'StartParsec'
    Write-Host 'Launched parsecd via scheduled task (Session 1)'
    Start-Sleep -Seconds 12

    Write-Host '=== parsecd processes ==='
    Get-WmiObject Win32_Process | Where-Object { $_.Name -eq 'parsecd.exe' } |
        Select-Object ProcessId, SessionId | Format-Table

    Write-Host '=== Parsec log (last 20 lines) ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\log.txt' | Select-Object -Last 20

    Write-Host '=== DLLs ==='
    Get-ChildItem 'C:\Users\bot\AppData\Roaming\Parsec\' -Filter '*.dll' | Select-Object Name
}
