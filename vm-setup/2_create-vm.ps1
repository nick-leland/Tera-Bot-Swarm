#Requires -RunAsAdministrator
# =============================================================================
# 2_create-vm.ps1 - Create the TeraBot1 VM
#
# What this does:
#   1. Creates a dynamic OS disk, partitions it via diskpart, applies Windows via DISM
#   2. Creates a game disk and copies all of D:\TERA Starscape into it (~68GB, takes a while)
#   3. Creates the Hyper-V VM and wires everything together
#   4. Checkpoints before first boot
#   5. Starts the VM - Windows completes setup automatically (~10-15 min)
#
# When done: VM will be at a Windows desktop logged in as 'bot'.
# Next step: run 3_configure-vm.ps1
# =============================================================================

. "$PSScriptRoot\config.ps1"

# --- Preflight checks ---
if (!(Test-Path $ISOPath)) {
    Write-Error "ISO not found: $ISOPath"
    exit 1
}
if (!(Test-Path $TeraSourcePath)) {
    Write-Error "TERA source not found: $TeraSourcePath"
    exit 1
}
if (Get-VM -Name $VMName -ErrorAction SilentlyContinue) {
    Write-Error "VM '$VMName' already exists. Delete it first if you want to recreate."
    exit 1
}

New-Item -ItemType Directory -Force -Path $VMPath | Out-Null

# --- 1. OS disk: create, partition, apply Windows ---
Write-Host "`n[1/5] Preparing OS disk with Windows (DISM)..." -ForegroundColor Cyan

if (Test-Path $VMOSDisk) { Remove-Item $VMOSDisk -Force }
New-VHD -Path $VMOSDisk -SizeBytes ($VMOSDiskGB * 1GB) -Dynamic | Out-Null

$vhd     = Mount-VHD -Path $VMOSDisk -PassThru
$diskNum = $vhd.DiskNumber

# Partition via diskpart (S: = EFI, W: = Windows)
$dpScript = @"
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
$dpScript | Out-File -FilePath $dpFile -Encoding ASCII
diskpart /s $dpFile | Out-Null
Remove-Item $dpFile -Force
Start-Sleep -Seconds 2

$efiDrive = "S:"
$winDrive = "W:"

# Mount ISO and select Windows Pro edition
$isoMount = Mount-DiskImage -ImagePath $ISOPath -PassThru
$isoDrive = ($isoMount | Get-Volume).DriveLetter + ":"
$wimPath  = "$isoDrive\sources\install.wim"
$images   = Get-WindowsImage -ImagePath $wimPath
$target   = $images | Where-Object { $_.ImageName -like "*Pro*" } | Select-Object -First 1
if (!$target) { $target = $images | Select-Object -First 1 }
Write-Host "  Applying: [$($target.ImageIndex)] $($target.ImageName) (5-10 min)..."

Expand-WindowsImage -ImagePath $wimPath -Index $target.ImageIndex -ApplyPath "$winDrive\" | Out-Null

# Write boot files - try host bcdboot first, fall back to bcdboot from applied image
$out = & cmd /c "bcdboot $winDrive\Windows /s $efiDrive /f UEFI 2>&1"
if ($LASTEXITCODE -ne 0) {
    $out = & cmd /c "$winDrive\Windows\System32\bcdboot.exe $winDrive\Windows /s $efiDrive /f UEFI 2>&1"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "bcdboot failed: $out"
        Dismount-VHD -Path $VMOSDisk
        Dismount-DiskImage -ImagePath $ISOPath | Out-Null
        exit 1
    }
}
Write-Host "  Boot files written."

# Inject unattend for first-boot OOBE (generated from config so credentials stay in sync)
$pantherDir = "$winDrive\Windows\Panther"
New-Item -ItemType Directory -Force -Path $pantherDir | Out-Null
@"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">

  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <ComputerName>$VMName</ComputerName>
      <TimeZone>UTC</TimeZone>
    </component>
  </settings>

  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">

      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <NetworkLocation>Work</NetworkLocation>
        <ProtectYourPC>3</ProtectYourPC>
        <SkipMachineOOBE>true</SkipMachineOOBE>
        <SkipUserOOBE>true</SkipUserOOBE>
      </OOBE>

      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Password>
              <Value>$VMPassword</Value>
              <PlainText>true</PlainText>
            </Password>
            <DisplayName>$VMUsername</DisplayName>
            <Group>Administrators</Group>
            <Name>$VMUsername</Name>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>

      <AutoLogon>
        <Password>
          <Value>$VMPassword</Value>
          <PlainText>true</PlainText>
        </Password>
        <Enabled>true</Enabled>
        <LogonCount>999</LogonCount>
        <Username>$VMUsername</Username>
      </AutoLogon>

    </component>
  </settings>

</unattend>
"@ | Out-File -FilePath "$pantherDir\unattend.xml" -Encoding UTF8
Write-Host "  Unattend injected (user: $VMUsername)."

Dismount-VHD -Path $VMOSDisk
Dismount-DiskImage -ImagePath $ISOPath | Out-Null
Write-Host "  OS disk ready."

# --- 2. Game disk (copy TERA into it) ---
Write-Host "`n[2/5] Creating game disk and copying TERA (~68GB - this takes 10-20 min)..." -ForegroundColor Cyan
if (Test-Path $VMGameDisk) { Remove-Item $VMGameDisk -Force }
New-VHD -Path $VMGameDisk -SizeBytes ($VMGameDiskGB * 1GB) -Dynamic | Out-Null

$gdisk    = Mount-VHD -Path $VMGameDisk -PassThru
$gdiskNum = $gdisk.DiskNumber
Initialize-Disk -Number $gdiskNum -PartitionStyle GPT -Confirm:$false
$gpart = New-Partition -DiskNumber $gdiskNum -UseMaximumSize -AssignDriveLetter
Format-Volume -DriveLetter $gpart.DriveLetter -FileSystem NTFS -NewFileSystemLabel "TeraGame" -Confirm:$false | Out-Null
$gameDrive = "$($gpart.DriveLetter):"

Write-Host "  Mounted game disk at $gameDrive, copying files..."
robocopy "$TeraSourcePath" "$gameDrive\TERA Starscape" /E /MT:8 /R:1 /W:1

Dismount-VHD -Path $VMGameDisk
Write-Host "  Game disk ready."

# --- 3. Create VM ---
Write-Host "`n[3/5] Creating VM '$VMName'..." -ForegroundColor Cyan

New-VM -Name $VMName -Generation 2 -MemoryStartupBytes $VMRAM -Path $VMBasePath -NoVHD | Out-Null
Set-VMProcessor -VMName $VMName -Count $VMvCPUs -ExposeVirtualizationExtensions $true
Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false
Set-VMFirmware -VMName $VMName -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows

# Required for GPU-P on Windows 11
Set-VM -VMName $VMName -GuestControlledCacheTypes $true `
    -LowMemoryMappedIoSpace 3GB -HighMemoryMappedIoSpace 32GB `
    -EnhancedSessionTransportType HvSocket

# Windows 11 requires TPM
Set-VMKeyProtector -VMName $VMName -NewLocalKeyProtector
Enable-VMTPM -VMName $VMName

Add-VMHardDiskDrive -VMName $VMName -Path $VMOSDisk  -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0
Add-VMHardDiskDrive -VMName $VMName -Path $VMGameDisk -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 1

Connect-VMNetworkAdapter -VMName $VMName -SwitchName $VMSwitchName

Write-Host "  VM '$VMName' created."

# --- 4. Checkpoint before first boot ---
Write-Host "`n[4/5] Creating restore point..." -ForegroundColor Cyan
Checkpoint-VM -Name $VMName -SnapshotName "pre-first-boot"
Write-Host "  Checkpoint 'pre-first-boot' saved."

# --- 5. Start VM ---
Write-Host "`n[5/5] Starting VM..." -ForegroundColor Cyan
Start-VM -Name $VMName

Write-Host ""
Write-Host "VM is booting - Windows completes setup automatically (~10-15 min)." -ForegroundColor Green
Write-Host "When you see a desktop logged in as 'bot', run 3_configure-vm.ps1"
