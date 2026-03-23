$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Stop pservice first so it won't relaunch parsecd
    Stop-Service 'Parsec' -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Kill all parsecd
    Stop-Process -Name parsecd -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    # Verify no parsecd running
    $running = Get-Process -Name parsecd -ErrorAction SilentlyContinue
    Write-Host "parsecd still running: $($running -ne $null)"

    # Now delete the DLL
    $dll = 'C:\Users\bot\AppData\Roaming\Parsec\parsecd-150-102b.dll'
    try {
        Remove-Item $dll -Force -ErrorAction Stop
        Write-Host 'Successfully deleted parsecd-150-102b.dll'
    } catch {
        Write-Host "Failed to delete: $_"
    }
    Write-Host "DLL still exists: $(Test-Path $dll)"

    # Restart pservice
    Start-Service 'Parsec' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 10

    # Check state
    Write-Host '=== parsecd processes ==='
    Get-WmiObject Win32_Process | Where-Object { $_.Name -eq 'parsecd.exe' } | Select-Object ProcessId, SessionId | Format-Table

    Write-Host '=== Parsec log new entries ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\log.txt' -ErrorAction SilentlyContinue | Select-Object -Last 20

    # Check if 102b redownloaded
    Write-Host '=== Parsec AppData DLLs ==='
    Get-ChildItem 'C:\Users\bot\AppData\Roaming\Parsec\' -Filter '*.dll' | Select-Object Name, Length
}
