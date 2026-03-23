. "$PSScriptRoot\config.ps1"

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host "=== Video Controllers ===" -ForegroundColor Cyan
    Get-WmiObject Win32_VideoController | Select-Object Name, Status, ConfigManagerErrorCode, DriverVersion | Format-List

    Write-Host "=== PnP Devices (NVIDIA) ===" -ForegroundColor Cyan
    Get-PnpDevice | Where-Object { $_.FriendlyName -like "*NVIDIA*" -or $_.FriendlyName -like "*Display*" } | Format-Table FriendlyName, Status, Class, InstanceId -AutoSize

    Write-Host "=== PnP Error Details ===" -ForegroundColor Cyan
    Get-PnpDevice | Where-Object { $_.Status -eq "Error" } | ForEach-Object {
        $err = $_ | Get-PnpDeviceProperty -KeyName DEVPKEY_Device_ProblemCode -ErrorAction SilentlyContinue
        Write-Host "$($_.FriendlyName): Problem code $($err.Data)"
    }
}
