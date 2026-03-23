$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Kill old standalone parsecd instances
    Stop-Process -Name parsecd -Force -ErrorAction SilentlyContinue
    Write-Host 'Killed old parsecd instances'
    Start-Sleep -Seconds 5

    # Check what pservice injected
    Write-Host '=== Processes ==='
    Get-WmiObject Win32_Process | Where-Object { $_.Name -like '*parsec*' -or $_.Name -like '*pservice*' } |
        Select-Object Name, ProcessId, SessionId | Format-Table -AutoSize

    # Check new log entries
    Write-Host '=== Parsec log (new entries after kill) ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\log.txt' -ErrorAction SilentlyContinue | Select-Object -Last 30
}
