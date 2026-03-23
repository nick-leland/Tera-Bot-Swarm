#Requires -RunAsAdministrator
# =============================================================================
# 6_bind-gpu-driver.ps1 - Properly sign a wrapper INF and bind NVIDIA to GPU-P
#
# Tools: makecat.exe + signtool.exe (both from Windows Kits 10, found on host)
#
# Flow:
#   HOST: create wrapper INF → makecat → sign with self-signed cert
#   VM:   add cert to TrustedPublisher → pnputil /add-driver /install → reboot
# =============================================================================

. "$PSScriptRoot\config.ps1"

$makecat  = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\makecat.exe"
$signtool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe"

# =============================================================================
# Determine RTX 5090 install section from NVIDIA INF
# =============================================================================
$driverStorePath = "C:\Windows\System32\DriverStore\FileRepository"
$nvFolder = Get-ChildItem $driverStorePath -Directory |
    Where-Object { $_.Name -match "^nv_dispi" } | Select-Object -First 1
$srcInf = "$($nvFolder.FullName)\nv_dispi.inf"

$hostGpuWmi = Get-WmiObject Win32_VideoController |
    Where-Object { $_.Name -like "*NVIDIA*" -and $_.Name -notlike "*Virtual*" } |
    Select-Object -First 1
if ($hostGpuWmi.PNPDeviceID -match 'DEV_([0-9A-Fa-f]{4})') { $devPart = "DEV_$($Matches[1])" }
else { Write-Error "Can't determine GPU device ID"; exit 1 }

$lines = Get-Content $srcInf
$gpuLine = $lines | Where-Object {
    $_ -match "=\s*.+,\s*PCI\\VEN_10DE&$([regex]::Escape($devPart))(&|\s*$)" -and $_ -match '='
} | Select-Object -First 1
if (!$gpuLine) { Write-Error "Can't find $devPart in INF"; exit 1 }
$sectionName = ($gpuLine -split '=')[1].Trim().Split(',')[0].Trim()
Write-Host "RTX 5090 install section: $sectionName"

# Get DriverVer from original INF
$driverVer = ($lines | Where-Object { $_ -match '^DriverVer' } | Select-Object -First 1) -replace '^DriverVer\s*=\s*',''
if (!$driverVer) { $driverVer = "12/02/2025,32.0.15.9144" }
Write-Host "DriverVer: $driverVer"

# =============================================================================
# Build wrapper INF, .cdf, .cat, sign everything
# =============================================================================
$workDir = "C:\nv_gpup_pkg"   # Short path avoids makecat ResultDir issues
if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force }
New-Item -ItemType Directory -Path $workDir | Out-Null

$wrapperInf = "$workDir\nv_gpup_wrapper.inf"
$cdfFile    = "$workDir\nv_gpup_wrapper.cdf"
$catFile    = "$workDir\nv_gpup_wrapper.cat"
$pfxFile    = "$workDir\test_signer.pfx"

# --- Wrapper INF ---
@"
; Wrapper INF: binds NVIDIA driver to Hyper-V GPU-P device (VEN_1414&DEV_008E)
; Delegates all install actions to the already-staged NVIDIA oem2.inf.

[Version]
Signature   = "`$Windows NT`$"
Provider    = %NVIDIA%
ClassGUID   = {4D36E968-E325-11CE-BFC1-08002BE10318}
Class       = Display
DriverVer   = $driverVer
CatalogFile = nv_gpup_wrapper.cat

[Manufacturer]
%NVIDIA%=NV_GPU_P,NTamd64.10.0.19041

[NV_GPU_P.NTamd64.10.0.19041]
%NVIDIA_GPUP% = Install_GPU_P, PCI\VEN_1414&DEV_008E

[Install_GPU_P]
Include = oem2.inf
Needs   = $sectionName

[Install_GPU_P.HW]
Include = oem2.inf
Needs   = $sectionName.HW

[Install_GPU_P.Services]
Include = oem2.inf
Needs   = $sectionName.Services

[Strings]
NVIDIA      = "NVIDIA"
NVIDIA_GPUP = "NVIDIA GeForce RTX 5090 (GPU-P)"
"@ | Set-Content $wrapperInf -Encoding ASCII

Write-Host "Wrapper INF written."

# --- Create self-signed code-signing certificate ---
Write-Host "Creating self-signed code-signing certificate..."
$cert = New-SelfSignedCertificate `
    -Subject "CN=NvGpuP Test Signer" `
    -CertStoreLocation "Cert:\LocalMachine\My" `
    -Type CodeSigningCert `
    -KeyUsage DigitalSignature `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears(5)

$certPass = ConvertTo-SecureString "gpuPtest123!" -AsPlainText -Force
Export-PfxCertificate -Cert $cert -FilePath $pfxFile -Password $certPass | Out-Null
# Also export the public cert (to add to VM's TrustedPublisher)
$cerFile = "$workDir\test_signer.cer"
Export-Certificate -Cert $cert -FilePath $cerFile -Type CERT | Out-Null
Write-Host "  Certificate thumbprint: $($cert.Thumbprint)"

# --- Build catalog definition file ---
@"
[CatalogHeader]
Name=nv_gpup_wrapper.cat
ResultDir=$workDir
PublicVersion=0x0000001
EncodingType=0x00010001
CATATTR1=0x10010001:OSAttr:2:6.0

[CatalogFiles]
<HASH>nv_gpup_wrapper.inf=$wrapperInf
"@ | Set-Content $cdfFile -Encoding ASCII

# --- Run makecat ---
Write-Host "Running makecat to create catalog..."
$result = & $makecat $cdfFile 2>&1
Write-Host ($result | Out-String)

if (!(Test-Path $catFile)) {
    Write-Error "makecat failed to create $catFile"
    exit 1
}
Write-Host "Catalog created: $catFile"

# --- Sign the catalog with signtool (standard Authenticode for .cat files) ---
Write-Host "Signing catalog with signtool..."
$result = & $signtool sign /fd SHA256 /f $pfxFile /p "gpuPtest123!" /v $catFile 2>&1
Write-Host ($result | Out-String)

if ($LASTEXITCODE -ne 0) {
    Write-Error "signtool failed to sign the catalog"
    exit 1
}

# Verify
$result = & $signtool verify /v $catFile 2>&1
Write-Host ($result | Out-String)

# =============================================================================
# Copy package (wrapper INF + cat + cert) to VM
# =============================================================================
Write-Host "Copying signed driver package to VM..."

Enable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface" -ErrorAction SilentlyContinue

# Wait for VM
$timeout = 120; $elapsed = 0
while ($elapsed -lt $timeout) {
    try {
        Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { 1 } -ErrorAction Stop | Out-Null
        break
    } catch { Start-Sleep -Seconds 10; $elapsed += 10; Write-Host "  Waiting for VM... ($elapsed s)" }
}

Write-Host "  Source files: $(Test-Path $wrapperInf) / $(Test-Path $catFile) / $(Test-Path $cerFile)"
Start-Sleep -Seconds 5   # give GSI a moment after PS Direct is ready
Copy-VMFile -Name $VMName -SourcePath $wrapperInf -DestinationPath "C:\NvGpuP\nv_gpup_wrapper.inf" -CreateFullPath -FileSource Host -Force
Copy-VMFile -Name $VMName -SourcePath $catFile    -DestinationPath "C:\NvGpuP\nv_gpup_wrapper.cat" -CreateFullPath -FileSource Host -Force
Copy-VMFile -Name $VMName -SourcePath $cerFile    -DestinationPath "C:\NvGpuP\test_signer.cer"     -CreateFullPath -FileSource Host -Force
Write-Host "  Files copied."

Remove-Item $workDir -Recurse -Force
# Clean up cert from host My store
Remove-Item "Cert:\LocalMachine\My\$($cert.Thumbprint)" -ErrorAction SilentlyContinue

# =============================================================================
# In VM: add cert to TrustedPublisher + install driver + reboot
# =============================================================================
$session = New-PSSession -VMName $VMName -Credential $VMCred

Invoke-Command -Session $session -ScriptBlock {

    Write-Host "=== BCD state ===" -ForegroundColor Cyan
    bcdedit /enum | Where-Object { $_ -match "testsigning|nointegrity|loadoption" }
    # Re-apply in case they didn't persist
    bcdedit /set testsigning on       2>&1 | ForEach-Object { Write-Host "  testsigning: $_" }
    bcdedit /set nointegritychecks on 2>&1 | ForEach-Object { Write-Host "  nointegrity: $_" }

    Write-Host ""
    Write-Host "=== Adding cert to TrustedPublisher ===" -ForegroundColor Cyan
    $cert = Import-Certificate -FilePath "C:\NvGpuP\test_signer.cer" -CertStoreLocation "Cert:\LocalMachine\TrustedPublisher"
    # Also add to Root to prevent chain errors
    Import-Certificate -FilePath "C:\NvGpuP\test_signer.cer" -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
    Write-Host "  Cert added: $($cert.Subject)"

    Write-Host ""
    Write-Host "=== oem2.inf presence ===" -ForegroundColor Cyan
    if (Test-Path "C:\Windows\INF\oem2.inf") {
        Write-Host "  oem2.inf EXISTS - NVIDIA driver is staged."
    } else {
        Write-Host "  oem2.inf NOT FOUND" -ForegroundColor Red
        pnputil /enum-drivers 2>&1 | Select-String "nv_|nvidia" | ForEach-Object { Write-Host "  $_" }
    }

    Write-Host ""
    Write-Host "=== Installing wrapper driver via pnputil ===" -ForegroundColor Cyan
    $result = pnputil /add-driver "C:\NvGpuP\nv_gpup_wrapper.inf" /install 2>&1
    Write-Host ($result -join "`n")

    Write-Host ""
    Write-Host "=== Device state ===" -ForegroundColor Cyan
    Get-PnpDevice | Where-Object { $_.InstanceId -like "*VEN_1414*" } |
        Format-Table FriendlyName, Status, InstanceId -AutoSize
}

Remove-PSSession $session

Restart-VM -Name $VMName -Force
Write-Host ""
Write-Host "VM rebooting. Connect via Parsec and check Device Manager." -ForegroundColor Green
