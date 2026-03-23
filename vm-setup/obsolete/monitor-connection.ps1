Start-Sleep -Seconds 30
$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host '=== Parsec log (last 40 lines) ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\log.txt' | Select-Object -Last 40
    Write-Host '=== NVIDIA ==='
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' } | Select-Object Status
    Write-Host '=== Displays ==='
    Get-WmiObject Win32_VideoController | Select-Object Name, CurrentHorizontalResolution, CurrentVerticalResolution | Format-Table -AutoSize
}
