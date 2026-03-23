$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host '=== Parsec service status ==='
    Get-Service 'Parsec' | Select-Object Name, Status, StartType

    Write-Host '=== All Parsec processes ==='
    Get-WmiObject Win32_Process | Where-Object { $_.Name -like '*parsec*' -or $_.Name -like '*pservice*' } |
        Select-Object Name, ProcessId, SessionId | Format-Table

    Write-Host '=== NVIDIA status ==='
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' } | Select-Object Status

    Write-Host '=== Full log from 17:40 onwards ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\log.txt' | Where-Object { $_ -match '17:[4-9]\d:|18:' -or $_ -match 'Started|version|release' }

    Write-Host '=== Application crash events (last 15 min) ==='
    Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000} -MaxEvents 20 -ErrorAction SilentlyContinue |
        Where-Object { $_.TimeCreated -gt (Get-Date).AddMinutes(-15) } |
        Select-Object TimeCreated, @{N='App';E={($_.Properties[0]).Value}}, @{N='Module';E={($_.Properties[3]).Value}} |
        Format-Table -AutoSize
}
