$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host '=== Displays ==='
    Get-WmiObject Win32_VideoController | Select-Object Name, CurrentHorizontalResolution, CurrentVerticalResolution | Format-Table -AutoSize

    Write-Host '=== parsecd command lines ==='
    Get-WmiObject Win32_Process | Where-Object { $_.Name -eq 'parsecd.exe' } |
        Select-Object ProcessId, SessionId, CommandLine | Format-List

    # Check if capture subprocess exists (different PID than loader)
    Write-Host '=== All parsecd threads/processes ==='
    Get-Process -Name parsecd | Select-Object Id, SessionId, MainWindowTitle, Threads

    Write-Host '=== log_cl.txt (client log, last 20 lines) ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\log_cl.txt' -ErrorAction SilentlyContinue | Select-Object -Last 20
}
