$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Kill parsecd
    Stop-Process -Name parsecd -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Delete the 102b DLL
    $dll = 'C:\Users\bot\AppData\Roaming\Parsec\parsecd-150-102b.dll'
    if (Test-Path $dll) {
        Remove-Item $dll -Force
        Write-Host 'Deleted parsecd-150-102b.dll'
    } else {
        Write-Host '102b DLL not present'
    }

    # Check all Parsec DLLs
    Write-Host '=== Parsec AppData files ==='
    Get-ChildItem 'C:\Users\bot\AppData\Roaming\Parsec\' | Select-Object Name, Length | Format-Table -AutoSize

    # Fix NVIDIA - start VirtualRender and re-enable device
    $vr = Get-Service 'VirtualRender' -ErrorAction SilentlyContinue
    if ($vr.Status -ne 'Running') { Start-Service 'VirtualRender' -ErrorAction SilentlyContinue; Start-Sleep 3 }

    $nvidia = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' }
    if ($nvidia.Status -ne 'OK') {
        Write-Host 'Fixing NVIDIA Code 43...'
        Disable-PnpDevice -InstanceId $nvidia.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 4
        Enable-PnpDevice -InstanceId $nvidia.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
    }
    $nvidia = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' }
    Write-Host "NVIDIA after fix: $($nvidia.Status)"

    # Let pservice reinject (wait)
    Start-Sleep -Seconds 8
    Write-Host '=== parsecd processes ==='
    Get-WmiObject Win32_Process | Where-Object { $_.Name -eq 'parsecd.exe' } | Select-Object ProcessId, SessionId | Format-Table
}
