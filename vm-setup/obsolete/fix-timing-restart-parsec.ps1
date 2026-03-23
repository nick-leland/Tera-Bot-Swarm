$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Increase launch delay to 30s so NVIDIA fix completes first
    $launchScript = "Start-Sleep -Seconds 30`nStart-Process 'C:\Program Files\Parsec\parsecd.exe'"
    [System.IO.File]::WriteAllText('C:\Users\bot\launch-parsec.ps1', $launchScript, [System.Text.Encoding]::UTF8)
    Write-Host 'launch-parsec.ps1 updated: 30s delay'

    # Kill old parsecd (started when NVIDIA was Error/WARP)
    Stop-Process -Name parsecd -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    Write-Host '=== NVIDIA now ==='
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' } | Select-Object Status, FriendlyName

    # Trigger the logon task to restart parsecd immediately
    Start-ScheduledTask -TaskName 'StartParsecAtLogon' -ErrorAction SilentlyContinue
    Write-Host 'Triggered StartParsecAtLogon task (30s delay before parsecd starts)'

    # Wait 40s for parsecd to start and initialize
    Start-Sleep -Seconds 40

    Write-Host '=== parsecd processes ==='
    Get-WmiObject Win32_Process | Where-Object { $_.Name -eq 'parsecd.exe' } |
        Select-Object ProcessId, SessionId, CommandLine | Format-List

    Write-Host '=== Parsec log (last 30 lines) ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\log.txt' -ErrorAction SilentlyContinue | Select-Object -Last 30
}
