$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Check ProgramData Parsec
    Write-Host '=== C:\ProgramData\Parsec ==='
    Get-ChildItem 'C:\ProgramData\Parsec' -ErrorAction SilentlyContinue | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize

    # Check pservice log
    Write-Host '=== pservice log search ==='
    $paths = @(
        'C:\ProgramData\Parsec\pservice.log',
        'C:\ProgramData\Parsec\log.txt',
        'C:\Windows\System32\config\systemprofile\AppData\Local\Temp\parsec.log',
        'C:\Windows\Temp\parsec.log',
        'C:\Windows\System32\config\systemprofile\AppData\Roaming\Parsec\log.txt'
    )
    foreach ($p in $paths) {
        if (Test-Path $p) {
            Write-Host "FOUND: $p"
            Get-Content $p | Select-Object -Last 30
        }
    }

    # Event log for pservice
    Write-Host '=== System events for Parsec service ==='
    Get-WinEvent -FilterHashtable @{LogName='System'} -MaxEvents 50 -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -like '*Parsec*' -or $_.Message -like '*pservice*' } |
        Select-Object TimeCreated, Id, Message | Select-Object -First 5 | Format-List

    # Also check Application log
    Write-Host '=== Application events for pservice ==='
    Get-WinEvent -FilterHashtable @{LogName='Application'} -MaxEvents 50 -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -like '*pservice*' -or $_.Message -like '*Parsec*' } |
        Where-Object { $_.TimeCreated -gt (Get-Date).AddMinutes(-10) } |
        Select-Object TimeCreated, Id, Message | Select-Object -First 5 | Format-List
}
