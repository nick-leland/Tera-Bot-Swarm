$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Check if explorer is running
    Write-Host '=== Explorer processes ==='
    Get-Process -Name explorer -ErrorAction SilentlyContinue | Select-Object Id, SessionId

    # Check display state
    Write-Host '=== Displays ==='
    Get-WmiObject Win32_VideoController | Select-Object Name, CurrentHorizontalResolution, CurrentVerticalResolution | Format-Table -AutoSize

    Write-Host '=== Hyper-V Video status ==='
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*Hyper-V Video*' } | Select-Object Status, FriendlyName

    # Kill current failing parsecd
    Stop-Process -Name parsecd -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Replace Run key with delayed launcher
    $launchScript = @'
Start-Sleep -Seconds 10
Start-Process 'C:\Program Files\Parsec\parsecd.exe'
'@
    [System.IO.File]::WriteAllText('C:\Users\bot\launch-parsec.ps1', $launchScript, [System.Text.Encoding]::UTF8)

    Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'Parsec' `
        -Value 'powershell.exe -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Users\bot\launch-parsec.ps1'
    Write-Host 'Run key updated with 10s delay launcher'

    # Start parsec manually now (with delay since shell is already up)
    Start-Sleep -Seconds 3
    Start-Process 'C:\Program Files\Parsec\parsecd.exe'
    Start-Sleep -Seconds 10

    Write-Host '=== parsecd status ==='
    Get-WmiObject Win32_Process | Where-Object { $_.Name -eq 'parsecd.exe' } |
        Select-Object ProcessId, SessionId | Format-Table

    Write-Host '=== Parsec log (last 20 lines) ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\log.txt' | Select-Object -Last 20
}
