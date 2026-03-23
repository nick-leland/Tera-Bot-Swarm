#Requires -RunAsAdministrator
# =============================================================================
# 9_sign-vrd-driver.ps1 - Create test-signed vrd package with Windows 11 vrd.sys
#
# Code 52 = unsigned driver package. With testsigning=Yes in BCD, we can install
# a test-signed package. This creates a new test-signed vrd package using the
# newer vrd.sys (10.0.26100.1150) from the host's Windows 11 DriverStore.
# =============================================================================

. "$PSScriptRoot\config.ps1"

$makecat  = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\makecat.exe"
$signtool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe"

# Host vrd package (Windows 11 26100 version)
$hostVrdDir = "C:\Windows\System32\DriverStore\FileRepository\vrd.inf_amd64_4dd0e6d66a75bb7e"

# =============================================================================
# Build test-signed vrd package
# =============================================================================
$workDir = "C:\vrd_pkg"
if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force }
New-Item -ItemType Directory -Path $workDir | Out-Null

$infFile = "$workDir\vrd.inf"
$sysFile = "$workDir\vrd.sys"
$catFile = "$workDir\vrd.cat"
$cdfFile = "$workDir\vrd.cdf"
$pfxFile = "$workDir\test_signer.pfx"
$cerFile = "$workDir\test_signer.cer"

# Copy the new vrd.sys
Copy-Item "$hostVrdDir\vrd.sys" $sysFile -Force
$sysVersion = (Get-Item $sysFile).VersionInfo.FileVersion
Write-Host "vrd.sys version: $sysVersion"

# Create modified vrd.inf (no PnpLockdown, with CatalogFile, test-sign-compatible)
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

Write-Host "vrd.inf written."

# Create self-signed code-signing certificate
Write-Host "Creating test certificate..."
$cert = New-SelfSignedCertificate `
    -Subject "CN=VrdGpuP Test Signer" `
    -CertStoreLocation "Cert:\LocalMachine\My" `
    -Type CodeSigningCert `
    -KeyUsage DigitalSignature `
    -KeyAlgorithm RSA -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears(5)

$certPass = ConvertTo-SecureString "vrdTest123!" -AsPlainText -Force
Export-PfxCertificate -Cert $cert -FilePath $pfxFile -Password $certPass | Out-Null
Export-Certificate -Cert $cert -FilePath $cerFile -Type CERT | Out-Null
Write-Host "  Thumbprint: $($cert.Thumbprint)"

# Create catalog definition
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

# Run makecat
Write-Host "Running makecat..."
$result = & $makecat $cdfFile 2>&1
Write-Host ($result | Out-String)

if (!(Test-Path $catFile)) { Write-Error "makecat failed"; exit 1 }
Write-Host "Catalog created: $catFile"

# Sign catalog
Write-Host "Signing catalog..."
$result = & $signtool sign /fd SHA256 /f $pfxFile /p "vrdTest123!" /v $catFile 2>&1
Write-Host ($result | Out-String)

if ($LASTEXITCODE -ne 0) { Write-Error "signtool failed"; exit 1 }

# =============================================================================
# Copy package to VM
# =============================================================================
Write-Host "Copying package to VM..."
$timeout = 60; $elapsed = 0
while ($elapsed -lt $timeout) {
    try { Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { 1 } -ErrorAction Stop | Out-Null; break }
    catch { Start-Sleep 10; $elapsed += 10; Write-Host "  Waiting ($elapsed s)" }
}

Copy-VMFile -Name $VMName -SourcePath $infFile -DestinationPath "C:\VrdPkg\vrd.inf" -CreateFullPath -FileSource Host -Force
Copy-VMFile -Name $VMName -SourcePath $sysFile -DestinationPath "C:\VrdPkg\vrd.sys" -CreateFullPath -FileSource Host -Force
Copy-VMFile -Name $VMName -SourcePath $catFile -DestinationPath "C:\VrdPkg\vrd.cat" -CreateFullPath -FileSource Host -Force
Copy-VMFile -Name $VMName -SourcePath $cerFile -DestinationPath "C:\VrdPkg\test_signer.cer" -CreateFullPath -FileSource Host -Force
Write-Host "  Files copied."

# Cleanup host
Remove-Item $workDir -Recurse -Force
Remove-Item "Cert:\LocalMachine\My\$($cert.Thumbprint)" -ErrorAction SilentlyContinue

# =============================================================================
# In VM: add cert + install driver
# =============================================================================
$session = New-PSSession -VMName $VMName -Credential $VMCred

Invoke-Command -Session $session -ScriptBlock {
    Write-Host "=== BCD state ===" -ForegroundColor Cyan
    bcdedit /enum | Select-String "testsign|nointegrit"

    Write-Host ""
    Write-Host "=== Adding test cert to TrustedPublisher ===" -ForegroundColor Cyan
    $cert = Import-Certificate -FilePath "C:\VrdPkg\test_signer.cer" -CertStoreLocation "Cert:\LocalMachine\TrustedPublisher"
    Import-Certificate -FilePath "C:\VrdPkg\test_signer.cer" -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
    Write-Host "  Cert added: $($cert.Subject)"

    Write-Host ""
    Write-Host "=== Installing test-signed vrd driver ===" -ForegroundColor Cyan
    $result = pnputil /add-driver "C:\VrdPkg\vrd.inf" /install 2>&1
    Write-Host ($result -join "`n")

    Write-Host ""
    Write-Host "=== Device state ===" -ForegroundColor Cyan
    Get-WmiObject Win32_PnPEntity | Where-Object { $_.DeviceID -like '*VEN_1414*' } |
        Select-Object Name, ConfigManagerErrorCode, DriverVersion

    Remove-Item "C:\VrdPkg" -Recurse -Force -ErrorAction SilentlyContinue
}

Remove-PSSession $session

Write-Host ""
Write-Host "Rebooting VM..." -ForegroundColor Cyan
Restart-VM -Name $VMName -Force
Write-Host "Done. Check Device Manager after reboot." -ForegroundColor Green
