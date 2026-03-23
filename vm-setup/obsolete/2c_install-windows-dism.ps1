#Requires -RunAsAdministrator
# =============================================================================
# 2c_install-windows-dism.ps1 - Apply Windows directly to the OS VHDX via DISM
#
# Bypasses the "Press any key to boot from DVD" problem entirely.
# Mounts the ISO on the host, applies the WIM image to the OS VHDX,
# makes it UEFI-bootable, injects the unattend for first boot.
# VM boots straight from the disk - no DVD, no keypress needed.
# =============================================================================

. "$PSScriptRoot\config.ps1"

# --- Stop VM and clear all checkpoints FIRST (before touching any disks) ---
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if ($vm -and $vm.State -ne "Off") {
    Write-Host "Stopping VM..."
    Stop-VM -Name $VMName -Force
    Start-Sleep -Seconds 3
}

Write-Host "Clearing any existing checkpoints..."
$snapshots = Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue
foreach ($snap in $snapshots) {
    try {
        Remove-VMSnapshot -VMSnapshot $snap -Confirm:$false -ErrorAction Stop
        Write-Host "  Removed checkpoint: $($snap.Name)"
    } catch {
        Write-Host "  Checkpoint '$($snap.Name)' could not be removed via API (broken reference) - continuing anyway." -ForegroundColor Yellow
    }
}
Start-Sleep -Seconds 2

# --- Wipe and recreate OS disk ---
Write-Host "`n[1/6] Recreating blank OS disk..." -ForegroundColor Cyan
Remove-VMHardDiskDrive -VMName $VMName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0 -ErrorAction SilentlyContinue
if (Test-Path $VMOSDisk) { Remove-Item $VMOSDisk -Force }
New-VHD -Path $VMOSDisk -SizeBytes ($VMOSDiskGB * 1GB) -Dynamic | Out-Null
Write-Host "  OS disk recreated."

# --- Mount VHDX and partition it via diskpart ---
# Using diskpart instead of PowerShell disk cmdlets - more reliable for VHD operations.
# Using S: (System/EFI) and W: (Windows) to avoid conflicts with existing drive letters.
Write-Host "`n[2/6] Partitioning OS disk (GPT/UEFI layout via diskpart)..." -ForegroundColor Cyan

$vhd     = Mount-VHD -Path $VMOSDisk -PassThru
$diskNum = $vhd.DiskNumber

$efiDrive = "S:"
$winDrive = "W:"

$diskpartScript = @"
select disk $diskNum
clean
convert gpt
create partition efi size=100
format quick fs=fat32 label=System
assign letter=S
create partition msr size=16
create partition primary
format quick fs=ntfs label=Windows
assign letter=W
exit
"@

$dpFile = "$env:TEMP\dp_vhd_setup.txt"
$diskpartScript | Out-File -FilePath $dpFile -Encoding ASCII
$dpOutput = diskpart /s $dpFile
Write-Host ($dpOutput -join "`n")
Remove-Item $dpFile -Force

# Give diskpart a moment to settle
Start-Sleep -Seconds 2

if (!(Test-Path "$efiDrive\")) {
    Write-Error "EFI partition ($efiDrive) not accessible after diskpart. Aborting."
    Dismount-VHD -Path $VMOSDisk
    exit 1
}
Write-Host "  EFI: $efiDrive   Windows: $winDrive"

# --- Mount ISO and find the right Windows edition ---
Write-Host "`n[3/6] Mounting ISO and selecting Windows edition..." -ForegroundColor Cyan

$isoMount  = Mount-DiskImage -ImagePath $ISOPath -PassThru
$isoDrive  = ($isoMount | Get-Volume).DriveLetter + ":"
$wimPath   = "$isoDrive\sources\install.wim"

Write-Host "  Available editions in this ISO:"
$images = Get-WindowsImage -ImagePath $wimPath
$images | ForEach-Object { Write-Host "    Index $($_.ImageIndex): $($_.ImageName)" }

$targetImage = $images | Where-Object { $_.ImageName -like "*Pro*" } | Select-Object -First 1
if (!$targetImage) {
    $targetImage = $images | Select-Object -First 1
    Write-Host "  'Pro' not found, using: $($targetImage.ImageName)" -ForegroundColor Yellow
} else {
    Write-Host "  Selected: [$($targetImage.ImageIndex)] $($targetImage.ImageName)"
}

# --- Apply Windows image ---
Write-Host "`n[4/6] Applying Windows image to disk (this takes 5-10 min)..." -ForegroundColor Cyan
Expand-WindowsImage -ImagePath $wimPath -Index $targetImage.ImageIndex -ApplyPath "$winDrive\" | Out-Null
Write-Host "  Image applied."

# --- Make UEFI bootable ---
Write-Host "`n[5/6] Writing boot files..." -ForegroundColor Cyan

# Try host bcdboot first
$bcdOutput = & cmd /c "bcdboot $winDrive\Windows /s $efiDrive /f UEFI 2>&1"
Write-Host "  bcdboot (host): $bcdOutput"

if ($LASTEXITCODE -ne 0) {
    # Fallback: run bcdboot from the applied Windows image itself
    Write-Host "  Host bcdboot failed, trying from applied image..." -ForegroundColor Yellow
    $bcdOutput = & cmd /c "$winDrive\Windows\System32\bcdboot.exe $winDrive\Windows /s $efiDrive /f UEFI 2>&1"
    Write-Host "  bcdboot (image): $bcdOutput"

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Both bcdboot attempts failed. Output: $bcdOutput"
        Dismount-VHD -Path $VMOSDisk
        Dismount-DiskImage -ImagePath $ISOPath -ErrorAction SilentlyContinue | Out-Null
        exit 1
    }
}

Write-Host "  Boot files written successfully."

# Inject unattend for first-boot OOBE (skips all setup screens, creates bot account)
$pantherDir = "$winDrive\Windows\Panther"
New-Item -ItemType Directory -Force -Path $pantherDir | Out-Null
Copy-Item "$PSScriptRoot\oobe-unattend.xml" "$pantherDir\unattend.xml" -Force
Write-Host "  Unattend injected -> $pantherDir\unattend.xml"

# --- Dismount everything ---
Dismount-VHD -Path $VMOSDisk
Dismount-DiskImage -ImagePath $ISOPath | Out-Null

# --- Re-attach OS disk and fix boot order ---
Write-Host "`n[6/6] Attaching disk to VM and creating checkpoint..." -ForegroundColor Cyan

Add-VMHardDiskDrive -VMName $VMName -Path $VMOSDisk -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0

# Boot from disk (no DVD needed anymore)
$bootOrder = (Get-VMFirmware -VMName $VMName).BootOrder
$diskEntry = $bootOrder | Where-Object { $_.Device -is [Microsoft.HyperV.PowerShell.HardDiskDrive] -and $_.Device.Path -eq $VMOSDisk }
$rest      = $bootOrder | Where-Object { $_ -ne $diskEntry }
Set-VMFirmware -VMName $VMName -BootOrder (@($diskEntry) + $rest) -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows

# Checkpoint before first boot
Checkpoint-VM -Name $VMName -SnapshotName "pre-windows-install"
Write-Host "  Checkpoint saved."

Start-VM -Name $VMName

Write-Host ""
Write-Host "VM is booting directly from disk - no keypress needed." -ForegroundColor Green
Write-Host "First boot runs Windows setup automatically (~10-15 min, may reboot once)."
Write-Host "When you see a desktop logged in as 'bot', run 3_configure-vm.ps1"
