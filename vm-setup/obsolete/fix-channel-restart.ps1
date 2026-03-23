$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Stop pservice and kill parsecd
    Stop-Service 'Parsec' -Force -ErrorAction SilentlyContinue
    Stop-Process -Name parsecd -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    # Delete 102b DLL
    $dll = 'C:\Users\bot\AppData\Roaming\Parsec\parsecd-150-102b.dll'
    Remove-Item $dll -Force -ErrorAction SilentlyContinue
    Write-Host "102b DLL deleted: $(-not (Test-Path $dll))"

    # Write config.json without app_channel (stay on default 'release'/101b)
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $obj = @(
        'See https://parsec.app/config for documentation and example. JSON must be valid before saving or file be will be erased.',
        [ordered]@{
            app_run_level = [ordered]@{ value = 1 }
        }
    )
    $json = $obj | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText('C:\Users\bot\AppData\Roaming\Parsec\config.json', $json, $utf8NoBom)
    Write-Host '=== New config.json ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\config.json'

    # Fix NVIDIA if needed
    $nvidia = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' }
    if ($nvidia.Status -ne 'OK') {
        Write-Host 'Fixing NVIDIA...'
        $vr = Get-Service 'VirtualRender'
        if ($vr.Status -ne 'Running') { Start-Service 'VirtualRender'; Start-Sleep 3 }
        Disable-PnpDevice -InstanceId $nvidia.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep 4
        Enable-PnpDevice -InstanceId $nvidia.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep 5
    }
    $nvidia = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' }
    Write-Host "NVIDIA: $($nvidia.Status)"

    # Start pservice
    Start-Service 'Parsec' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 15

    # Check result
    Write-Host '=== Parsec processes ==='
    Get-WmiObject Win32_Process | Where-Object { $_.Name -like '*parsec*' -or $_.Name -like '*pservice*' } |
        Select-Object Name, ProcessId, SessionId | Format-Table

    Write-Host '=== Parsec log (last 30 lines) ==='
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\log.txt' | Select-Object -Last 30

    Write-Host '=== DLLs in Parsec AppData ==='
    Get-ChildItem 'C:\Users\bot\AppData\Roaming\Parsec\' -Filter '*.dll' | Select-Object Name, Length
}
