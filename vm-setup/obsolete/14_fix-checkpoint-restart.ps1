. "$PSScriptRoot\config.ps1"

# Disable automatic checkpoints - incompatible with GPU-P VMs
Set-VM -VMName $VMName -AutomaticCheckpointsEnabled $false -CheckpointType Disabled
Write-Host "Automatic checkpoints disabled (required for GPU-P VMs)."

# Restart
$state = (Get-VM -Name $VMName).State
Write-Host "Current state: $state"

if ($state -eq "Running") {
    Stop-VM -Name $VMName -Force
    $waited = 0
    while ((Get-VM -Name $VMName).State -ne "Off" -and $waited -lt 30) {
        Start-Sleep 3; $waited += 3
    }
}

Start-VM -Name $VMName
Write-Host "VM starting..."
Start-Sleep 5
Write-Host "State: $((Get-VM -Name $VMName).State)"
