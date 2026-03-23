$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Start the dismiss task immediately
    Start-ScheduledTask -TaskName 'Parsec-Dismiss-Dialog' -ErrorAction SilentlyContinue
    Write-Host 'Started Parsec-Dismiss-Dialog task'

    # Check VDD - needs to have a resolution for DXGI capture
    Write-Host '=== Display adapters ==='
    Get-WmiObject Win32_VideoController | Select-Object Name, CurrentHorizontalResolution, CurrentVerticalResolution | Format-Table -AutoSize

    # Fix NVIDIA
    $nvidia = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' }
    Write-Host "NVIDIA status: $($nvidia.Status)"
    if ($nvidia.Status -ne 'OK') {
        $vr = Get-Service 'VirtualRender'
        if ($vr.Status -ne 'Running') { Start-Service 'VirtualRender'; Start-Sleep 3 }
        Disable-PnpDevice -InstanceId $nvidia.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep 4
        Enable-PnpDevice -InstanceId $nvidia.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep 5
        Write-Host "NVIDIA after fix: $((Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' }).Status)"
    }

    # Check display adapters after NVIDIA fix
    Write-Host '=== Display adapters after NVIDIA fix ==='
    Get-WmiObject Win32_VideoController | Select-Object Name, CurrentHorizontalResolution, CurrentVerticalResolution | Format-Table -AutoSize

    # Check Parsec VDD - is it started?
    Write-Host '=== Parsec VDD service ==='
    Get-PnpDevice | Where-Object { $_.InstanceId -like 'ROOT\DISPLAY*' } | Select-Object Status, FriendlyName, InstanceId

    # Check if VDD needs to be started
    $vddExe = 'C:\Program Files\Parsec\vdd\parsec-vdd.exe'
    if (Test-Path $vddExe) {
        Write-Host 'VDD exe exists'
    }
}
