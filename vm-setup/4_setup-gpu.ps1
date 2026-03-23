#Requires -RunAsAdministrator
# =============================================================================
# 4_setup-gpu.ps1 - Attach GPU partition to VM and copy NVIDIA drivers offline
#
# What this does:
#   1. Stops VM, configures Hyper-V GPU-P settings
#   2. Mounts the OS VHD offline
#   3. Copies GPU driver files into the VHD using Add-VMGpuPartitionAdapterFiles
#      (places them in C:\Windows\System32\HostDriverStore - no pnputil needed)
#   4. Unmounts the VHD and starts the VM
#
# After this: GPU should appear in Device Manager and Parsec will use it.
# =============================================================================

. "$PSScriptRoot\config.ps1"

# =============================================================================
# STEP 1: Stop VM and configure GPU-P
# =============================================================================
Write-Host "`n[1/4] Configuring GPU-P on VM '$VMName'..." -ForegroundColor Cyan

$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (!$vm) { Write-Error "VM '$VMName' not found."; exit 1 }

if ($vm.State -ne "Off") {
    Write-Host "  Stopping VM..."
    Stop-VM -Name $VMName -Force
    Start-Sleep -Seconds 5
}

# Remove existing GPU partition if present, then add fresh
$existing = Get-VMGpuPartitionAdapter -VMName $VMName -ErrorAction SilentlyContinue
if ($existing) {
    Remove-VMGpuPartitionAdapter -VMName $VMName
    Write-Host "  Removed existing GPU partition adapter."
}
Add-VMGpuPartitionAdapter -VMName $VMName

# Standard resource values - enough for one bot VM
Set-VMGpuPartitionAdapter -VMName $VMName `
    -MinPartitionVRAM     80000000    -MaxPartitionVRAM     4000000000 -OptimalPartitionVRAM     4000000000 `
    -MinPartitionEncode   80000000    -MaxPartitionEncode   4000000000 -OptimalPartitionEncode   4000000000 `
    -MinPartitionDecode   80000000    -MaxPartitionDecode   4000000000 -OptimalPartitionDecode   4000000000 `
    -MinPartitionCompute  80000000    -MaxPartitionCompute  4000000000 -OptimalPartitionCompute  4000000000

Write-Host "  GPU partition adapter configured."

# Ensure MMIO and cache settings are correct (idempotent, safe to set again)
Set-VM -VMName $VMName -GuestControlledCacheTypes $true `
    -LowMemoryMappedIoSpace 3GB -HighMemoryMappedIoSpace 32GB
Write-Host "  MMIO settings confirmed."

# Remove any checkpoints so the VHD chain is flat before we mount it offline.
# Checkpoints create differencing disks (AVHDs) on top of the base VHDX - mounting
# the base directly while an AVHD exists breaks the chain.
$snapshots = Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue
if ($snapshots) {
    Write-Host "  Removing $($snapshots.Count) checkpoint(s) to flatten VHD chain..."
    $snapshots | Remove-VMSnapshot -IncludeAllChildSnapshots
    # Wait for Hyper-V to finish merging - check file locks, not just VM status,
    # because status can read "Off" while the merge is still writing disk blocks.
    Write-Host "  Waiting for checkpoint merge to complete..."
    Start-Sleep -Seconds 5
    do {
        Start-Sleep -Seconds 5
        $avhds = Get-ChildItem "$VMPath\*.avhdx" -ErrorAction SilentlyContinue
    } while ($avhds.Count -gt 0)
    Write-Host "  Checkpoints removed and merged."
}

# =============================================================================
# STEP 2: Mount OS VHD offline and copy GPU driver files
# =============================================================================
Write-Host "`n[2/4] Mounting OS VHD offline..." -ForegroundColor Cyan

Import-Module "$EasyGpuPvPath\Add-VMGpuPartitionAdapterFiles.psm1" -Force

# Get the actual path the VM uses - not the hardcoded base path.
# After a merge, Hyper-V reconfigures the VM to point to the base VHDX automatically.
$osDiskPath = (Get-VMHardDiskDrive -VMName $VMName | Where-Object { $_.ControllerLocation -eq 0 }).Path
Write-Host "  OS disk: $osDiskPath"
$vhd = Mount-VHD -Path $osDiskPath -PassThru
$DriveLetter = ($vhd | Get-Disk | Get-Partition | Get-Volume |
    Where-Object { $_.DriveLetter } | ForEach-Object DriveLetter)

if (!$DriveLetter) {
    Dismount-VHD -Path $osDiskPath
    Write-Error "Could not determine drive letter for mounted VHD."
    exit 1
}

Write-Host "  OS VHD mounted at $DriveLetter`:"

# =============================================================================
# STEP 3: Copy GPU driver files into the VHD
# =============================================================================
Write-Host "`n[3/4] Copying GPU drivers into VHD (this may take a minute)..." -ForegroundColor Cyan

try {
    Add-VMGpuPartitionAdapterFiles -DriveLetter $DriveLetter -GPUName "AUTO"
    Write-Host "  GPU driver files copied to VHD."
}
finally {
    Dismount-VHD -Path $osDiskPath
    Write-Host "  OS VHD dismounted."
}

# =============================================================================
# STEP 4: Start VM
# =============================================================================
Write-Host "`n[4/4] Starting VM..." -ForegroundColor Cyan
Enable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface" -ErrorAction SilentlyContinue
Start-VM -Name $VMName

Write-Host ""
Write-Host "GPU-P setup complete." -ForegroundColor Green
Write-Host "After the VM boots:"
Write-Host "  - Connect via Parsec"
Write-Host "  - Check Device Manager - NVIDIA GPU should appear under 'Display adapters'"
Write-Host "  - Parsec will automatically use the GPU for encoding"
