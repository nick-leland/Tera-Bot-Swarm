Start-Sleep -Seconds 20
$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host '=== Parsec processes ==='
    Get-WmiObject Win32_Process | Where-Object { $_.Name -like '*parsec*' -or $_.Name -like '*pservice*' } |
        Select-Object Name, ProcessId, SessionId | Format-Table

    Write-Host '=== Parsec log (new entries only) ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\log.txt' | Select-Object -Last 25

    Write-Host '=== DLLs ==='
    Get-ChildItem 'C:\Users\bot\AppData\Roaming\Parsec\' -Filter '*.dll' | Select-Object Name, Length

    Write-Host '=== NVIDIA ==='
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' } | Select-Object Status
}
