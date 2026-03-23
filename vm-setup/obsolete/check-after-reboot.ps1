Start-Sleep -Seconds 20
$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host '=== VirtualRender ==='
    (Get-Service 'VirtualRender').Status

    Write-Host '=== NVIDIA ==='
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' } | Select-Object Status, FriendlyName

    Write-Host '=== NVIDIA fix log ==='
    if (Test-Path 'C:\Windows\Temp\nvidia-fix.log') { Get-Content 'C:\Windows\Temp\nvidia-fix.log' }

    Write-Host '=== Parsec service ==='
    (Get-Service 'Parsec').Status

    Write-Host '=== All Parsec processes ==='
    Get-WmiObject Win32_Process | Where-Object { $_.Name -like '*parsec*' -or $_.Name -like '*pservice*' } |
        Select-Object Name, ProcessId, SessionId | Format-Table -AutoSize

    Write-Host '=== Sessions ==='
    query session 2>&1

    Write-Host '=== Parsec log (last 50 lines) ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\log.txt' -ErrorAction SilentlyContinue | Select-Object -Last 50
}
