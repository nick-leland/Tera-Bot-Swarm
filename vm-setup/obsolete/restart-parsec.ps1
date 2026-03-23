$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Fix config to standalone mode
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $obj = @(
        'See https://parsec.app/config for documentation and example. JSON must be valid before saving or file be will be erased.',
        [ordered]@{
            app_block_hash  = [ordered]@{ value = 'b4e1daaee72eb9ea621918eaa4293a50bcf9c4d71fb545325b7dcd8b0e858f34' }
            app_channel     = [ordered]@{ value = 'release17' }
            app_run_level   = [ordered]@{ value = 0 }
            encoder_bitrate = [ordered]@{ value = 20 }
            host_fps        = [ordered]@{ value = 30 }
        }
    )
    $json = $obj | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText('C:\Users\bot\AppData\Roaming\Parsec\config.json', $json, $utf8NoBom)
    Write-Host 'Config reset to standalone (app_run_level: 0)'

    # Kill old parsecd
    Stop-Process -Name parsecd -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Write-Host 'parsecd stopped'

    # Trigger the logon task (has 30s delay built in)
    Start-ScheduledTask -TaskName 'StartParsecAtLogon' -ErrorAction SilentlyContinue
    Write-Host 'StartParsecAtLogon triggered - waiting 40s for parsecd to start...'
    Start-Sleep -Seconds 40

    Write-Host '=== parsecd processes ==='
    Get-WmiObject Win32_Process | Where-Object { $_.Name -eq 'parsecd.exe' } |
        Select-Object ProcessId, SessionId, CommandLine | Format-List

    Write-Host '=== Parsec log (last 30 lines) ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\log.txt' -ErrorAction SilentlyContinue | Select-Object -Last 30
}
