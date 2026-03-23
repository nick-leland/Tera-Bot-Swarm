#Requires -RunAsAdministrator
# =============================================================================
# 2b_recover-vm.ps1 - Recover from a failed Windows install
#
# Use this when: VM won't boot, shows "Press any key" then PXE, or install failed.
# What it does:
#   - Stops the VM if running
#   - Wipes and recreates the OS disk (blank again)
#   - Recreates the autounattend disk
#   - Fixes the DVD boot order
#   - Creates a checkpoint BEFORE booting
#   - Starts the VM
#
# Does NOT touch the game disk - TERA files are preserved.
# =============================================================================

. "$PSScriptRoot\config.ps1"

# --- Stop VM if running ---
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (!$vm) {
    Write-Error "VM '$VMName' not found."
    exit 1
}
if ($vm.State -ne "Off") {
    Write-Host "Stopping VM '$VMName'..."
    Stop-VM -Name $VMName -Force
    Start-Sleep -Seconds 3
}

# --- Wipe and recreate OS disk ---
Write-Host "`n[1/4] Recreating blank OS disk..." -ForegroundColor Cyan

Remove-VMHardDiskDrive -VMName $VMName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0 -ErrorAction SilentlyContinue
if (Test-Path $VMOSDisk) { Remove-Item $VMOSDisk -Force }

New-VHD -Path $VMOSDisk -SizeBytes ($VMOSDiskGB * 1GB) -Dynamic | Out-Null
Add-VMHardDiskDrive -VMName $VMName -Path $VMOSDisk -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0
Write-Host "  OS disk recreated (blank)."

# --- Recreate autounattend disk ---
Write-Host "`n[2/4] Recreating autounattend disk..." -ForegroundColor Cyan

Remove-VMHardDiskDrive -VMName $VMName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 2 -ErrorAction SilentlyContinue
if (Test-Path $VMUnattendDisk) { Remove-Item $VMUnattendDisk -Force }

New-VHD -Path $VMUnattendDisk -SizeBytes 50MB -Fixed | Out-Null
$uDisk = Mount-VHD -Path $VMUnattendDisk -Passthru
Initialize-Disk -Number $uDisk.DiskNumber -PartitionStyle MBR -Confirm:$false
$uPart = New-Partition -DiskNumber $uDisk.DiskNumber -UseMaximumSize -AssignDriveLetter
Format-Volume -DriveLetter $uPart.DriveLetter -FileSystem FAT32 -Confirm:$false | Out-Null
Copy-Item "$PSScriptRoot\autounattend.xml" "$($uPart.DriveLetter):\"
Dismount-VHD -Path $VMUnattendDisk
Add-VMHardDiskDrive -VMName $VMName -Path $VMUnattendDisk -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 2
Write-Host "  Autounattend disk recreated."

# --- Fix Secure Boot + boot order ---
Write-Host "`n[3/4] Fixing Secure Boot and boot order..." -ForegroundColor Cyan

# Gen 2 VMs need Secure Boot ON with MicrosoftWindows template to boot Win10 ISO
Set-VMFirmware -VMName $VMName -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows

$bootOrder = (Get-VMFirmware -VMName $VMName).BootOrder
$dvdEntry  = $bootOrder | Where-Object { $_.Device -is [Microsoft.HyperV.PowerShell.DvdDrive] }
$diskEntry = $bootOrder | Where-Object { $_.Device -is [Microsoft.HyperV.PowerShell.HardDiskDrive] -and $_.Device.Path -eq $VMOSDisk }
$rest      = $bootOrder | Where-Object { $_ -ne $dvdEntry -and $_ -ne $diskEntry }

if ($dvdEntry) {
    Set-VMFirmware -VMName $VMName -BootOrder (@($dvdEntry, $diskEntry) + $rest)
    Write-Host "  Boot order: DVD → OS disk → other"
} else {
    Write-Host "  DVD drive not found in boot order - checking DVD drive is attached..." -ForegroundColor Yellow
    $dvd = Get-VMDvdDrive -VMName $VMName
    if (!$dvd) {
        Add-VMDvdDrive -VMName $VMName -Path $ISOPath
        Write-Host "  DVD drive re-attached."
    }
    $bootOrder = (Get-VMFirmware -VMName $VMName).BootOrder
    $dvdEntry  = $bootOrder | Where-Object { $_.Device -is [Microsoft.HyperV.PowerShell.DvdDrive] }
    $diskEntry = $bootOrder | Where-Object { $_.Device -is [Microsoft.HyperV.PowerShell.HardDiskDrive] -and $_.Device.Path -eq $VMOSDisk }
    $rest      = $bootOrder | Where-Object { $_ -ne $dvdEntry -and $_ -ne $diskEntry }
    Set-VMFirmware -VMName $VMName -BootOrder (@($dvdEntry, $diskEntry) + $rest)
}

# --- Checkpoint before boot ---
Write-Host "`n[4/4] Creating checkpoint and starting VM..." -ForegroundColor Cyan

# Remove old failed checkpoint if it exists
Get-VMSnapshot -VMName $VMName -Name "pre-windows-install" -ErrorAction SilentlyContinue | Remove-VMSnapshot
Checkpoint-VM -Name $VMName -SnapshotName "pre-windows-install"
Write-Host "  Checkpoint 'pre-windows-install' saved."

Start-VM -Name $VMName

Write-Host ""
Write-Host "VM started." -ForegroundColor Green
Write-Host "Open Hyper-V Manager and connect to the VM console NOW."
Write-Host "When you see 'Press any key to boot from CD or DVD...' - press a key immediately."
Write-Host ""
Write-Host "After that, Windows installs itself unattended (~15-20 min)."
Write-Host "When you see a desktop logged in as 'bot', run 3_configure-vm.ps1"
