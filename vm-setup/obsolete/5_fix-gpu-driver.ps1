#Requires -RunAsAdministrator
# =============================================================================
# 5_fix-gpu-driver.ps1 - Bind the NVIDIA driver to the Hyper-V GPU-P device
#
# Why this is needed:
#   GPU-P devices appear in the VM as PCI\VEN_1414&DEV_008E (Microsoft virtual
#   GPU partition). NVIDIA's nv_dispi.inf has no entry for this hardware ID, so
#   Windows never selects the NVIDIA driver.
#
# Approach:
#   1. Disable Secure Boot on VM (allows test signing / nointegritychecks)
#   2. Patch nv_dispi.inf: add VEN_1414&DEV_008E -> correct RTX 5090 section
#   3. In VM: enable nointegritychecks, reboot (activates DSE bypass)
#   4. In VM: copy staged DriverStore folder + replace INF, run DISM /ForceUnsigned
#   5. Reboot - NVIDIA driver binds to GPU-P device
# =============================================================================

. "$PSScriptRoot\config.ps1"

# =============================================================================
# STEP 1: Disable Secure Boot
# =============================================================================
Write-Host "`n[1/5] Disabling Secure Boot on VM..." -ForegroundColor Cyan

$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (!$vm) { Write-Error "VM '$VMName' not found."; exit 1 }

if ($vm.State -ne "Off") {
    Write-Host "  Stopping VM..."
    Stop-VM -Name $VMName -Force
    Start-Sleep -Seconds 5
}

Set-VMFirmware -VMName $VMName -EnableSecureBoot Off
Write-Host "  Secure Boot disabled."

# =============================================================================
# STEP 2: Patch nv_dispi.inf
# =============================================================================
Write-Host "`n[2/5] Patching NVIDIA INF for GPU-P..." -ForegroundColor Cyan

$driverStorePath = "C:\Windows\System32\DriverStore\FileRepository"
$nvFolder = Get-ChildItem $driverStorePath -Directory |
    Where-Object { $_.Name -match "^nv_dispi" } | Select-Object -First 1
if (!$nvFolder) { Write-Error "NVIDIA DriverStore folder not found."; exit 1 }

$srcInf = "$($nvFolder.FullName)\nv_dispi.inf"

$hostGpu = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -like "*NVIDIA*" -and $_.Status -eq "OK" } |
    Select-Object -First 1
if (!$hostGpu) { Write-Error "NVIDIA display device not found on host."; exit 1 }

$hostGpuWmi = Get-WmiObject Win32_VideoController |
    Where-Object { $_.Name -like "*NVIDIA*" -and $_.Name -notlike "*Virtual*" } |
    Select-Object -First 1

if (!$hostGpuWmi -or !$hostGpuWmi.PNPDeviceID) {
    Write-Error "Could not get NVIDIA GPU PNPDeviceID via WMI."
    exit 1
}

# PNPDeviceID format: "PCI\VEN_10DE&DEV_2B85&SUBSYS_xxxxyyyy&REV_xx\n&m..."
if ($hostGpuWmi.PNPDeviceID -match 'DEV_([0-9A-Fa-f]{4})') {
    $devHex  = $Matches[1]
    $devPart = "DEV_$devHex"
} else {
    Write-Error "Could not parse device ID from PNPDeviceID: $($hostGpuWmi.PNPDeviceID)"
    exit 1
}
Write-Host "  Host GPU: $($hostGpu.FriendlyName)"
Write-Host "  PNPDeviceID: $($hostGpuWmi.PNPDeviceID)"
Write-Host "  Device ID: $devPart"

$lines = Get-Content $srcInf

# Match the line where devPart is the actual PCI device ID (not a SUBSYS field).
# Pattern: "= SectionXXX, PCI\VEN_10DE&DEV_xxxx" followed by end-of-line or "&SUBSYS"
$gpuLine = $lines | Where-Object {
    $_ -match "=\s*.+,\s*PCI\\VEN_10DE&$([regex]::Escape($devPart))(&|\s*$)" -and $_ -match '='
} | Select-Object -First 1

if (!$gpuLine) {
    Write-Error "Could not find '$devPart' as a hardware ID in $srcInf"
    exit 1
}

$sectionName = ($gpuLine -split '=')[1].Trim().Split(',')[0].Trim()
Write-Host "  Found: $($gpuLine.Trim())"
Write-Host "  Install section: $sectionName"

$hvHwLine  = "%NVIDIA_HyperV% = $sectionName, PCI\VEN_1414&DEV_008E"
$hvStrLine = 'NVIDIA_HyperV = "NVIDIA GeForce RTX 5090 (GPU-P)"'

$newLines = [System.Collections.Generic.List[string]]::new()
$addedHw  = $false
$addedStr = $false

foreach ($line in $lines) {
    # Remove PnpLockdown and CatalogFile - both trigger strict catalog verification
    # that fails when INF is modified. nointegritychecks on the VM covers driver loading.
    if ($line -match '^\s*PnpLockdown'  ) { continue }
    if ($line -match '^\s*CatalogFile'  ) { continue }

    $newLines.Add($line)
    if (!$addedHw -and $line -eq $gpuLine) {
        $newLines.Add($hvHwLine)
        $addedHw = $true
    }
    if (!$addedStr -and $line -match '^\[Strings\]') {
        $newLines.Add($hvStrLine)
        $addedStr = $true
    }
}

if (!$addedHw) { Write-Error "Failed to insert hardware ID line."; exit 1 }

# Write as UTF-8 no-BOM (safe for all INF parsers including DISM)
$patchedInf = "$env:TEMP\nv_dispi_gpup.inf"
[System.IO.File]::WriteAllLines($patchedInf, $newLines,
    [System.Text.UTF8Encoding]::new($false))
Write-Host "  Patched INF written: $hvHwLine"

# =============================================================================
# STEP 3: Start VM, enable nointegritychecks, reboot (activates bypass)
# =============================================================================
Write-Host "`n[3/5] Starting VM, enabling driver signature bypass..." -ForegroundColor Cyan

Enable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface" -ErrorAction SilentlyContinue
Start-VM -Name $VMName

$timeout = 180; $elapsed = 0
while ($elapsed -lt $timeout) {
    try {
        Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { 1 } -ErrorAction Stop | Out-Null
        Write-Host "  VM ready."
        break
    } catch { Start-Sleep -Seconds 10; $elapsed += 10 }
}
if ($elapsed -ge $timeout) { Write-Error "VM did not become ready."; exit 1 }

# Copy patched INF to VM
Copy-VMFile -Name $VMName -SourcePath $patchedInf -DestinationPath "C:\nv_dispi_gpup.inf" `
    -CreateFullPath -FileSource Host -Force
Remove-Item $patchedInf -Force
Write-Host "  Patched INF copied to VM."

$session = New-PSSession -VMName $VMName -Credential $VMCred
Invoke-Command -Session $session -ScriptBlock {
    bcdedit /set testsigning on        2>&1 | ForEach-Object { Write-Host "  testsigning: $_" }
    bcdedit /set nointegritychecks on  2>&1 | ForEach-Object { Write-Host "  nointegrity: $_" }
}
Remove-PSSession $session

Write-Host "  Rebooting VM (reboot 1/2 - activates nointegritychecks)..."
Restart-VM -Name $VMName -Force

# =============================================================================
# STEP 4: After reboot, use DISM /ForceUnsigned to install the patched driver
# =============================================================================
Write-Host "`n[4/5] Waiting for VM to reboot..." -ForegroundColor Cyan

Start-Sleep -Seconds 25
$timeout = 180; $elapsed = 0
while ($elapsed -lt $timeout) {
    try {
        Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { 1 } -ErrorAction Stop | Out-Null
        Write-Host "  VM ready after reboot."
        break
    } catch { Start-Sleep -Seconds 10; $elapsed += 10 }
}
if ($elapsed -ge $timeout) { Write-Error "VM did not come back after reboot."; exit 1 }

$session = New-PSSession -VMName $VMName -Credential $VMCred
Invoke-Command -Session $session -ScriptBlock {

    # Find the NVIDIA staged driver folder in DriverStore\FileRepository
    $fileRepo = "C:\Windows\System32\DriverStore\FileRepository"
    $nvDir = Get-ChildItem $fileRepo -Directory |
        Where-Object { $_.Name -like "nv_dispi*" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (!$nvDir) {
        Write-Host "  ERROR: No staged NVIDIA folder in DriverStore!" -ForegroundColor Red
        return
    }
    Write-Host "  Staged NVIDIA folder: $($nvDir.Name)"

    # Copy DriverStore folder to a writable temp location
    $tempDir = "C:\NvDriverTemp"
    Write-Host "  Copying driver folder to temp..."
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    Copy-Item $nvDir.FullName $tempDir -Recurse -Force

    # Replace the INF with our patched version
    Copy-Item "C:\nv_dispi_gpup.inf" "$tempDir\nv_dispi.inf" -Force
    Remove-Item "C:\nv_dispi_gpup.inf" -Force -ErrorAction SilentlyContinue
    Write-Host "  Replaced INF with GPU-P patched version."

    # Try pnputil with the patched INF (PnpLockdown + CatalogFile removed).
    # nointegritychecks is active so the driver can load unsigned after reboot.
    Write-Host "  Running pnputil /add-driver /install (nointegritychecks is active)..."
    $result = pnputil /add-driver "$tempDir\nv_dispi.inf" /install 2>&1
    Write-Host ($result -join "`n")

    # Registry fallback: map VEN_1414&DEV_008E directly to the original staged NVIDIA package.
    # This works even if pnputil above failed, because oem2.inf is already WHQL-signed & staged.
    Write-Host ""
    Write-Host "  Adding DriverDatabase registry mapping (VEN_1414&DEV_008E -> NVIDIA)..."
    $pkgs = Get-ChildItem "HKLM:\SYSTEM\DriverDatabase\DriverPackages" -ErrorAction SilentlyContinue
    $nvPkg = $pkgs | Where-Object { $_.PSChildName -like "*nv_dispi*" } | Select-Object -First 1
    if ($nvPkg) {
        $pkgKeyName = $nvPkg.PSChildName
        Write-Host "  NVIDIA package: $pkgKeyName"
        $rankData = $null
        foreach ($key in (Get-ChildItem "HKLM:\SYSTEM\DriverDatabase\DeviceIds\PCI" -ErrorAction SilentlyContinue)) {
            if ($key.PSChildName -match "VEN_10DE") {
                $prop = Get-ItemProperty $key.PSPath -Name $pkgKeyName -ErrorAction SilentlyContinue
                if ($prop -and $null -ne $prop.$pkgKeyName) { $rankData = $prop.$pkgKeyName; break }
            }
        }
        if ($null -eq $rankData) { $rankData = [byte[]](0xFF, 0xFF, 0x00, 0x00) }
        $tgt = "HKLM:\SYSTEM\DriverDatabase\DeviceIds\PCI\VEN_1414&DEV_008E"
        if (!(Test-Path $tgt)) { New-Item -Path $tgt -Force | Out-Null }
        New-ItemProperty -Path $tgt -Name $pkgKeyName -Value $rankData -PropertyType Binary -Force | Out-Null
        Write-Host "  Registry mapping added." -ForegroundColor Green
        pnputil /scan-devices 2>&1 | Out-Null
    } else {
        Write-Host "  WARNING: nv_dispi package not found in DriverDatabase." -ForegroundColor Yellow
        Write-Host "  Listing all packages:"
        $pkgs | ForEach-Object { Write-Host "    $($_.PSChildName)" }
    }

    Remove-Item $tempDir -Recurse -Force

    Write-Host ""
    Write-Host "  Device state after install:"
    Get-PnpDevice | Where-Object { $_.InstanceId -like "*VEN_1414*" } |
        Format-Table FriendlyName, Status, InstanceId -AutoSize
}
Remove-PSSession $session

# =============================================================================
# STEP 5: Final reboot
# =============================================================================
Write-Host "`n[5/5] Final reboot to load NVIDIA driver on GPU-P device..." -ForegroundColor Cyan
Restart-VM -Name $VMName -Force

Write-Host ""
Write-Host "Done. Connect via Parsec after reboot and check Device Manager." -ForegroundColor Green
Write-Host "NVIDIA GeForce RTX 5090 should show OK under Display adapters."
