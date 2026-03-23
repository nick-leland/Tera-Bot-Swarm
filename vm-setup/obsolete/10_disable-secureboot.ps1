#Requires -RunAsAdministrator
# =============================================================================
# 10_disable-secureboot.ps1 - Disable Secure Boot + fix test-signed vrd driver
#
# Root cause of Code 52: VM was created with Secure Boot ON (MicrosoftWindows
# template). Secure Boot overrides BCD testsigning=on and refuses ANY driver
# package not signed by Microsoft's production WHQL cert. bcdedit's testsigning
# is only effective when Secure Boot is OFF.
#
# Fix:
#   HOST: Stop VM → disable Secure Boot → start VM
#   VM:   verify CI TestMode is now set → re-add test cert → rescan device
# =============================================================================

. "$PSScriptRoot\config.ps1"

$makecat  = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\makecat.exe"
$signtool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe"

# Host vrd package (Windows 11 26100 version)
$hostVrdDir = "C:\Windows\System32\DriverStore\FileRepository\vrd.inf_amd64_4dd0e6d66a75bb7e"

# =============================================================================
# Step 1: Disable Secure Boot (requires VM to be off)
# =============================================================================
Write-Host "=== Disabling Secure Boot ===" -ForegroundColor Cyan

$vmState = (Get-VM -Name $VMName).State
if ($vmState -ne "Off") {
    Write-Host "  VM is running - stopping it..."
    Stop-VM -Name $VMName -Force
    $waited = 0
    while ((Get-VM -Name $VMName).State -ne "Off" -and $waited -lt 60) {
        Start-Sleep 3; $waited += 3
    }
    Write-Host "  VM stopped."
}

$fw = Get-VMFirmware -VMName $VMName
Write-Host "  Current Secure Boot: $($fw.SecureBoot)"

if ($fw.SecureBoot -ne "Off") {
    Set-VMFirmware -VMName $VMName -EnableSecureBoot Off
    Write-Host "  Secure Boot DISABLED." -ForegroundColor Green
} else {
    Write-Host "  Secure Boot already off." -ForegroundColor Green
}

# =============================================================================
# Step 2: Re-build and re-sign the test vrd package on host
#   (cert from previous run was deleted; need a fresh one)
# =============================================================================
Write-Host ""
Write-Host "=== Building test-signed vrd package ===" -ForegroundColor Cyan

$workDir = "C:\vrd_pkg"
if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force }
New-Item -ItemType Directory -Path $workDir | Out-Null

$infFile = "$workDir\vrd.inf"
$sysFile = "$workDir\vrd.sys"
$catFile = "$workDir\vrd.cat"
$cdfFile = "$workDir\vrd.cdf"
$pfxFile = "$workDir\test_signer.pfx"
$cerFile = "$workDir\test_signer.cer"

# Copy Windows 11 vrd.sys
Copy-Item "$hostVrdDir\vrd.sys" $sysFile -Force
# Strip the (WinBuild...) suffix that makes the version unparseable as a 4-tuple
$sysVersion = ((Get-Item $sysFile).VersionInfo.FileVersion -replace '\s*\(.*\)', '').Trim()
Write-Host "  vrd.sys version: $sysVersion"

@"
;
; Virtual Render Driver INF (test-signed for GPU-P)
; vrd.sys version: $sysVersion
;

[Version]
Signature   = "`$Windows NT`$"
Class       = Display
ClassGUID   = {4d36e968-e325-11ce-bfc1-08002be10318}
Provider    = %MS%
ClassVer    = 2.0
CatalogFile = vrd.cat
DriverVer   = 06/21/2006,$sysVersion

[SourceDisksNames]
1 = VirtualRenderDisk

[SourceDisksFiles]
vrd.sys = 1

[DestinationDirs]
VirtualRender.Miniport = 13

[Manufacturer]
%MS% = VirtualRender.Mfg, NTamd64

[ControlFlags]
ExcludeFromSelect = *
PreConfigureDriver = *

[VirtualRender.Mfg.NTamd64]
%VirtualRender.DeviceDesc% = VirtualRender_Inst, PCI\VEN_1414&DEV_008E

[VirtualRender_Inst]
FeatureScore = FB
CopyFiles    = VirtualRender.Miniport

[VirtualRender.Miniport]
vrd.sys,,,0x100

[VirtualRender_Inst.Services]
AddService = VirtualRender, 0x00000002, VirtualRender_Service_Inst

[VirtualRender_Service_Inst]
ServiceType   = %SERVICE_KERNEL_DRIVER%
StartType     = %SERVICE_DEMAND_START%
ErrorControl  = %SERVICE_ERROR_IGNORE%
ServiceBinary = %13%\vrd.sys

[Strings]
SERVICE_BOOT_START   = 0x0
SERVICE_SYSTEM_START = 0x1
SERVICE_AUTO_START   = 0x2
SERVICE_DEMAND_START = 0x3
SERVICE_DISABLED     = 0x4
SERVICE_KERNEL_DRIVER = 0x1
SERVICE_ERROR_IGNORE  = 0x0
SERVICE_ERROR_NORMAL  = 0x1
MS = "Microsoft"
VirtualRender.DeviceDesc = "Microsoft Virtual Render Driver (GPU-P)"
"@ | Set-Content $infFile -Encoding ASCII

Write-Host "  vrd.inf written."

# Self-signed code-signing cert
Write-Host "  Creating test certificate..."
$cert = New-SelfSignedCertificate `
    -Subject "CN=VrdGpuP Test Signer" `
    -CertStoreLocation "Cert:\LocalMachine\My" `
    -Type CodeSigningCert `
    -KeyUsage DigitalSignature `
    -KeyAlgorithm RSA -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears(10)

$certPass = ConvertTo-SecureString "vrdTest123!" -AsPlainText -Force
Export-PfxCertificate -Cert $cert -FilePath $pfxFile -Password $certPass | Out-Null
Export-Certificate    -Cert $cert -FilePath $cerFile -Type CERT | Out-Null
Write-Host "  Thumbprint: $($cert.Thumbprint)"

# Catalog definition
@"
[CatalogHeader]
Name=vrd.cat
ResultDir=$workDir
PublicVersion=0x0000001
EncodingType=0x00010001
CATATTR1=0x10010001:OSAttr:2:6.0

[CatalogFiles]
<HASH>vrd.inf=$infFile
<HASH>vrd.sys=$sysFile
"@ | Set-Content $cdfFile -Encoding ASCII

Write-Host "  Running makecat..."
$result = & $makecat $cdfFile 2>&1
Write-Host ($result | Out-String)
if (!(Test-Path $catFile)) { Write-Error "makecat failed"; exit 1 }

Write-Host "  Signing catalog..."
$result = & $signtool sign /fd SHA256 /f $pfxFile /p "vrdTest123!" /v $catFile 2>&1
Write-Host ($result | Out-String)
if ($LASTEXITCODE -ne 0) { Write-Error "signtool failed"; exit 1 }

# =============================================================================
# Step 3: Start VM and wait
# =============================================================================
Write-Host ""
Write-Host "=== Starting VM ===" -ForegroundColor Cyan
Start-VM -Name $VMName

$timeout = 180; $elapsed = 0
Write-Host "  Waiting for VM to accept PS sessions..."
while ($elapsed -lt $timeout) {
    try {
        Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { 1 } -ErrorAction Stop | Out-Null
        Write-Host "  VM ready." -ForegroundColor Green
        break
    } catch {
        Start-Sleep 10; $elapsed += 10
        Write-Host "  Waiting ($elapsed s)..."
    }
}
if ($elapsed -ge $timeout) { Write-Error "VM not ready after $timeout s"; exit 1 }

# =============================================================================
# Step 4: Copy package to VM
# =============================================================================
Write-Host ""
Write-Host "=== Copying package to VM ===" -ForegroundColor Cyan
Start-Sleep 5   # let GSI settle

Copy-VMFile -Name $VMName -SourcePath $infFile -DestinationPath "C:\VrdPkg\vrd.inf"          -CreateFullPath -FileSource Host -Force
Copy-VMFile -Name $VMName -SourcePath $sysFile -DestinationPath "C:\VrdPkg\vrd.sys"          -CreateFullPath -FileSource Host -Force
Copy-VMFile -Name $VMName -SourcePath $catFile -DestinationPath "C:\VrdPkg\vrd.cat"          -CreateFullPath -FileSource Host -Force
Copy-VMFile -Name $VMName -SourcePath $cerFile -DestinationPath "C:\VrdPkg\test_signer.cer"  -CreateFullPath -FileSource Host -Force
Write-Host "  Files copied."

# Cleanup host
Remove-Item $workDir -Recurse -Force
Remove-Item "Cert:\LocalMachine\My\$($cert.Thumbprint)" -ErrorAction SilentlyContinue

# =============================================================================
# Step 5: In VM - verify CI TestMode, install cert, install driver
# =============================================================================
$session = New-PSSession -VMName $VMName -Credential $VMCred

Invoke-Command -Session $session -ScriptBlock {

    # --- Verify Secure Boot is gone and testsigning is active ---
    Write-Host "=== BCD state ===" -ForegroundColor Cyan
    bcdedit /enum | Select-String "testsign|nointegrit"

    Write-Host ""
    Write-Host "=== CI TestMode (should now be set) ===" -ForegroundColor Cyan
    $testMode = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CI" -Name "TestMode" -ErrorAction SilentlyContinue)
    if ($testMode) {
        Write-Host "  TestMode = $($testMode.TestMode)" -ForegroundColor Green
        Write-Host "  Testsigning IS active at kernel level." -ForegroundColor Green
    } else {
        Write-Host "  TestMode NOT SET - testsigning may need a reboot to take effect" -ForegroundColor Yellow
        Write-Host "  (This is normal on first boot after Secure Boot was disabled)"
    }

    # --- Add cert to TrustedPublisher and Root ---
    Write-Host ""
    Write-Host "=== Adding test cert to trust stores ===" -ForegroundColor Cyan
    $cert = Import-Certificate -FilePath "C:\VrdPkg\test_signer.cer" -CertStoreLocation "Cert:\LocalMachine\TrustedPublisher"
    Import-Certificate -FilePath "C:\VrdPkg\test_signer.cer" -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
    Write-Host "  Cert added to TrustedPublisher: $($cert.Subject)"
    Write-Host "  Cert thumbprint: $($cert.Thumbprint)"

    # Verify it's actually there
    $inStore = Get-ChildItem "Cert:\LocalMachine\TrustedPublisher" | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
    if ($inStore) { Write-Host "  Verified in TrustedPublisher store." -ForegroundColor Green }
    else { Write-Host "  WARNING: cert not found in store after import!" -ForegroundColor Red }

    # --- Install driver ---
    Write-Host ""
    Write-Host "=== Installing test-signed vrd driver ===" -ForegroundColor Cyan
    $result = pnputil /add-driver "C:\VrdPkg\vrd.inf" /install 2>&1
    Write-Host ($result -join "`n")

    Write-Host ""
    Write-Host "=== Current staged vrd drivers ===" -ForegroundColor Cyan
    pnputil /enum-drivers 2>&1 | Select-String "vrd|VirtualRender|oem" | ForEach-Object { Write-Host "  $_" }

    Write-Host ""
    Write-Host "=== GPU-P device state ===" -ForegroundColor Cyan
    Get-PnpDevice | Where-Object { $_.InstanceId -like "*VEN_1414*" } |
        Format-Table FriendlyName, Status, InstanceId -AutoSize

    Remove-Item "C:\VrdPkg" -Recurse -Force -ErrorAction SilentlyContinue
}

Remove-PSSession $session

Write-Host ""
Write-Host "=== Rebooting VM ===" -ForegroundColor Cyan
Write-Host "(Reboot needed for driver change to take effect)"
Restart-VM -Name $VMName -Force

Write-Host ""
Write-Host "Done. After reboot (~30s):" -ForegroundColor Green
Write-Host "  1. Check Parsec/Device Manager - GPU-P device should show working (no error code)"
Write-Host "  2. Look for 'Test Mode' watermark on the desktop - confirms testsigning is active"
Write-Host "  3. Run query-gpu5.ps1 to verify CI TestMode registry key is now set"
