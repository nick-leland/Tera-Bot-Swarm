#Requires -RunAsAdministrator
. "$PSScriptRoot\config.ps1"

$osVhdx    = "C:\VirtualMachines\TeraBot1\TeraBot1-os.vhdx"
$gameAvhdx = "C:\VirtualMachines\TeraBot1\TeraBot1-game_E95D129F-8BF3-4D85-A3D1-1616591824EA.avhdx"
$gameChain = @(
    "C:\VirtualMachines\TeraBot1\TeraBot1-game_BFC5B03F-4DE3-49C6-BFEE-8E80ECE46BB9.avhdx",
    "C:\VirtualMachines\TeraBot1\TeraBot1-game_8A6801B3-4165-4C68-87F1-68BC75F51152.avhdx",
    "C:\VirtualMachines\TeraBot1\TeraBot1-game_544F5F60-8151-4DB3-A591-4BDB5219CA51.avhdx",
    "C:\VirtualMachines\TeraBot1\TeraBot1-game_4188DB64-A403-430A-A8D6-5A638E634D0A.avhdx",
    "C:\VirtualMachines\TeraBot1\TeraBot1-game.vhdx"
)

# Remove all snapshots (frees the AVHDX locks)
Write-Host "=== Removing snapshots ===" -ForegroundColor Cyan
Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-VMSnapshot -VMSnapshot $_ -ErrorAction SilentlyContinue
    Write-Host "  Removed: $($_.Name)"
}
Start-Sleep 5

# Point OS disk directly at the merged parent VHDX (bypassing the broken AVHDX)
Write-Host ""
Write-Host "=== Updating OS disk to merged parent VHDX ===" -ForegroundColor Cyan
Set-VMHardDiskDrive -VMName $VMName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0 -Path $osVhdx
Write-Host "  OS disk -> $osVhdx" -ForegroundColor Green

# Fix game disk chain with IgnoreIdMismatch all the way up
Write-Host ""
Write-Host "=== Fixing game disk parent chain ===" -ForegroundColor Cyan
$prev = $gameAvhdx
foreach ($p in $gameChain) {
    Set-VHD -Path $prev -ParentPath $p -IgnoreIdMismatch -ErrorAction SilentlyContinue
    Write-Host "  $([IO.Path]::GetFileName($prev)) -> $([IO.Path]::GetFileName($p))"
    $prev = $p
}

# Verify
Write-Host ""
Write-Host "=== VM disk config after fix ===" -ForegroundColor Cyan
Get-VMHardDiskDrive -VMName $VMName | Format-Table ControllerLocation, Path

# Start VM
Write-Host ""
Write-Host "=== Starting VM ===" -ForegroundColor Cyan
Start-VM -Name $VMName
$state = (Get-VM -Name $VMName).State
Write-Host "State: $state" -ForegroundColor $(if ($state -eq 'Running') { 'Green' } else { 'Red' })
