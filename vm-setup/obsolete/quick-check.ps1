. "$PSScriptRoot\config.ps1"
Start-Sleep 20
$timeout = 90; $elapsed = 0
while ($elapsed -lt $timeout) {
    try {
        Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { 1 } -ErrorAction Stop | Out-Null
        Write-Host "VM ready."
        break
    } catch { Start-Sleep 10; $elapsed += 10; Write-Host "  $elapsed s..." }
}

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host "=== BCD (testsigning) ==="
    bcdedit /enum | Select-String "testsign|nointegrit"

    Write-Host "=== CI TestMode ==="
    (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CI" -Name "TestMode" -ErrorAction SilentlyContinue)

    Write-Host "=== GPU-P devices ==="
    Get-PnpDevice | Where-Object { $_.InstanceId -like "*VEN_1414*" } | Format-Table FriendlyName, Status, InstanceId -AutoSize

    Write-Host "=== Latest CI events ==="
    Get-WinEvent -LogName "Microsoft-Windows-CodeIntegrity/Operational" -MaxEvents 5 -ErrorAction SilentlyContinue |
        Format-Table TimeCreated, Id, Message -Wrap
}
