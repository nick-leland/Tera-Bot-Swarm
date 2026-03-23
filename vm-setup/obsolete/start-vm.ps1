. "$PSScriptRoot\config.ps1"

$vm = Get-VM -Name $VMName
Write-Host "Current state: $($vm.State)"

if ($vm.State -eq "Off") {
    Start-VM -Name $VMName
    Write-Host "Starting $VMName..."
    $waited = 0
    while ((Get-VM -Name $VMName).State -ne "Running" -and $waited -lt 30) {
        Start-Sleep 3; $waited += 3
    }
    Write-Host "State: $((Get-VM -Name $VMName).State)"
} elseif ($vm.State -eq "Running") {
    Write-Host "VM is already running."
} else {
    Write-Host "VM is in state: $($vm.State) - may need manual intervention"
}
