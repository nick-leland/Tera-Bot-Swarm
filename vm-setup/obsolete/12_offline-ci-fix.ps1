#Requires -RunAsAdministrator
# =============================================================================
# 12_offline-ci-fix.ps1 - Fix driver signing enforcement offline
#
# Problem: driversipolicy.p7b in C:\Windows\System32\CodeIntegrity\ enforces
# Microsoft WHQL signing requirements on ALL kernel drivers, overriding BCD
# testsigning=Yes and nointegritychecks=Yes completely.
#
# Fix (offline, VM must be Off):
#   1. Mount the OS AVHDX offline
#   2. Rename driversipolicy.p7b (disables strict driver signing policy)
#   3. Also set testsigning=Yes in BCD (via offline /store method)
#   4. Unmount, start VM
# =============================================================================
. "$PSScriptRoot\config.ps1"

# --- Stop VM ---
$vmState = (Get-VM -Name $VMName).State
if ($vmState -ne "Off") {
    Write-Host "Stopping VM..."
    Stop-VM -Name $VMName -TurnOff:$false
    $waited = 0
    while ((Get-VM -Name $VMName).State -ne "Off" -and $waited -lt 60) {
        Start-Sleep 5; $waited += 5
    }
    if ((Get-VM -Name $VMName).State -ne "Off") {
        Stop-VM -Name $VMName -Force
        Start-Sleep 5
    }
    Write-Host "VM stopped."
}

# --- Find OS disk ---
$osDisk = (Get-VMHardDiskDrive -VMName $VMName | Where-Object { $_.ControllerLocation -eq 0 }).Path
Write-Host "OS disk: $osDisk"

# --- Mount offline ---
Write-Host "Mounting disk offline..."
$disk = Mount-VHD -Path $osDisk -PassThru | Get-Disk
$diskNum = $disk.Number

# Find Windows partition (NTFS, largest)
$winPart = Get-Partition -DiskNumber $diskNum | Where-Object { $_.Size -gt 20GB } | Select-Object -First 1
$efiFart  = Get-Partition -DiskNumber $diskNum | Where-Object { $_.Size -lt 200MB -and $_.Size -gt 50MB } | Select-Object -First 1

Set-Partition -DiskNumber $diskNum -PartitionNumber $winPart.PartitionNumber -NewDriveLetter W
Set-Partition -DiskNumber $diskNum -PartitionNumber $efiFart.PartitionNumber -NewDriveLetter X

Write-Host "Windows drive: W:"
Write-Host "EFI drive: X:"

# --- Disable driversipolicy.p7b ---
Write-Host ""
Write-Host "=== Disabling driver signing policy ===" -ForegroundColor Cyan
$ciPath = "W:\Windows\System32\CodeIntegrity"
$policyFile = "$ciPath\driversipolicy.p7b"
$vbsPolicy  = "$ciPath\VbsSiPolicy.p7b"

if (Test-Path $policyFile) {
    Rename-Item $policyFile "$ciPath\driversipolicy.p7b.bak" -Force
    Write-Host "  Renamed driversipolicy.p7b -> driversipolicy.p7b.bak" -ForegroundColor Green
} else {
    Write-Host "  driversipolicy.p7b not found" -ForegroundColor Yellow
}

if (Test-Path $vbsPolicy) {
    Rename-Item $vbsPolicy "$ciPath\VbsSiPolicy.p7b.bak" -Force
    Write-Host "  Renamed VbsSiPolicy.p7b -> VbsSiPolicy.p7b.bak" -ForegroundColor Green
}

# Verify
Write-Host ""
Write-Host "  CI folder contents after:"
Get-ChildItem $ciPath | Format-Table Name, Length

# --- Fix BCD testsigning ---
Write-Host ""
Write-Host "=== Setting BCD testsigning (offline) ===" -ForegroundColor Cyan
$bcdPath = "X:\EFI\Microsoft\Boot\BCD"
if (Test-Path $bcdPath) {
    bcdedit /store $bcdPath /set "{default}" testsigning on
    bcdedit /store $bcdPath /set "{default}" nointegritychecks on
    Write-Host "  Verification:"
    bcdedit /store $bcdPath /enum | Where-Object { $_ -match "testsign|nointegrit" }
    # Show the full default entry to confirm
    bcdedit /store $bcdPath /enum "{default}" | Select-String "testsign|nointegrit|identifier"
} else {
    Write-Host "  BCD not found at $bcdPath" -ForegroundColor Red
}

# --- Unmount ---
Write-Host ""
Write-Host "=== Unmounting ===" -ForegroundColor Cyan
Remove-PartitionAccessPath -DiskNumber $diskNum -PartitionNumber $winPart.PartitionNumber -AccessPath "W:\"
Remove-PartitionAccessPath -DiskNumber $diskNum -PartitionNumber $efiFart.PartitionNumber -AccessPath "X:\"
Dismount-VHD -Path $osDisk
Write-Host "Unmounted." -ForegroundColor Green

# --- Start VM ---
Write-Host ""
Write-Host "=== Starting VM ===" -ForegroundColor Cyan
Start-VM -Name $VMName

$timeout = 150; $elapsed = 0
Write-Host "Waiting for VM..."
while ($elapsed -lt $timeout) {
    try {
        Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { 1 } -ErrorAction Stop | Out-Null
        Write-Host "VM ready." -ForegroundColor Green
        break
    } catch { Start-Sleep 10; $elapsed += 10; Write-Host "  $elapsed s..." }
}

# --- Verify inside VM ---
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host "=== CI policy files ===" -ForegroundColor Cyan
    Get-ChildItem "C:\Windows\System32\CodeIntegrity" | Format-Table Name, Length

    Write-Host ""
    Write-Host "=== BCD (testsigning) ===" -ForegroundColor Cyan
    bcdedit /enum | Select-String "testsign|nointegrit"

    Write-Host ""
    Write-Host "=== CI TestMode ===" -ForegroundColor Cyan
    $tm = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CI" -Name "TestMode" -ErrorAction SilentlyContinue
    if ($tm) { Write-Host "  TestMode = $($tm.TestMode)" -ForegroundColor Green }
    else { Write-Host "  TestMode not set" -ForegroundColor Yellow }

    Write-Host ""
    Write-Host "=== Latest CI events ===" -ForegroundColor Cyan
    Get-WinEvent -LogName "Microsoft-Windows-CodeIntegrity/Operational" -MaxEvents 5 -ErrorAction SilentlyContinue |
        Format-Table TimeCreated, Id, Message -Wrap

    Write-Host ""
    Write-Host "=== GPU-P device state ===" -ForegroundColor Cyan
    Get-PnpDevice | Where-Object { $_.InstanceId -like "*VEN_1414*" } |
        Format-Table FriendlyName, Status, InstanceId -AutoSize
}
