$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Restart pservice to pick up new config
    Restart-Service -Name 'Parsec' -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 10

    Write-Host '=== Service status ==='
    (Get-Service 'Parsec').Status

    Write-Host '=== All parsec processes ==='
    Get-WmiObject Win32_Process | Where-Object { $_.Name -like '*parsec*' -or $_.Name -like '*pservice*' } |
        Select-Object Name, ProcessId, SessionId | Format-Table -AutoSize

    Write-Host '=== Parsec log new entries ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\log.txt' -ErrorAction SilentlyContinue | Select-Object -Last 20
}
