#Requires -RunAsAdministrator
# =============================================================================
# 8_copy-hostdriverstore.ps1 - GPU-P via HostDriverStore (Easy-GPU-PV method)
#
# GPU-P does NOT use normal PnP/pnputil for the NVIDIA driver.
# dxgkrnl.sys loads the NVIDIA driver from HostDriverStore\FileRepository\.
# This script replicates what Easy-GPU-PV does.
# =============================================================================

. "$PSScriptRoot\config.ps1"

# =============================================================================
# Find NVIDIA driver folder on host
# =============================================================================
Write-Host "Finding NVIDIA driver folder on host..." -ForegroundColor Cyan

$driverStorePath = "C:\Windows\System32\DriverStore\FileRepository"
$nvFolder = Get-ChildItem $driverStorePath -Directory |
    Where-Object { $_.Name -match "^nv_dispi" } |
    Sort-Object {
        (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
         Measure-Object -Property Length -Sum).Sum
    } -Descending | Select-Object -First 1

if (!$nvFolder) { Write-Error "NVIDIA driver folder not found in DriverStore."; exit 1 }
$folderSizeMB = [math]::Round((Get-ChildItem $nvFolder.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB, 0)
Write-Host "  Using: $($nvFolder.Name) ($folderSizeMB MB)"

# System32 DLLs the VM needs for GPU-P
$gpuDlls = @(
    "nvapi64.dll",
    "nvwgf2umx.dll",
    "nvcuvid.dll",
    "nvEncodeAPI64.dll",
    "nvml.dll",
    "nvdxgiwrap.dll",
    "nvcuda.dll",
    "nvofapi64.dll"
) | Where-Object { Test-Path "C:\Windows\System32\$_" }

Write-Host "  System32 DLLs to copy: $($gpuDlls.Count)"

# =============================================================================
# Bundle into zip
# =============================================================================
Write-Host "Bundling into zip archive..." -ForegroundColor Cyan

$stagingDir = "$env:TEMP\NvGpuP_HS_Staging"
$zipPath    = "$env:TEMP\NvGpuP_HS.zip"

Remove-Item $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $zipPath    -Force -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Force -Path "$stagingDir\DriverStore\$($nvFolder.Name)" | Out-Null
New-Item -ItemType Directory -Force -Path "$stagingDir\System32" | Out-Null

Write-Host "  Copying DriverStore folder (may take a moment)..."
Copy-Item "$($nvFolder.FullName)\*" "$stagingDir\DriverStore\$($nvFolder.Name)\" -Recurse -Force

Write-Host "  Copying System32 DLLs..."
foreach ($dll in $gpuDlls) {
    Copy-Item "C:\Windows\System32\$dll" "$stagingDir\System32\" -Force
}

Write-Host "  Compressing..."
Compress-Archive -Path "$stagingDir\*" -DestinationPath $zipPath -Force
$zipSizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 0)
Write-Host "  Archive: $zipPath ($zipSizeMB MB)"
Remove-Item $stagingDir -Recurse -Force

# =============================================================================
# Wait for VM + copy zip
# =============================================================================
Write-Host "Waiting for VM..." -ForegroundColor Cyan
$timeout = 120; $elapsed = 0
while ($elapsed -lt $timeout) {
    try {
        Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { 1 } -ErrorAction Stop | Out-Null
        Write-Host "  VM ready."
        break
    } catch { Start-Sleep 10; $elapsed += 10; Write-Host "  Waiting ($elapsed s)" }
}
if ($elapsed -ge $timeout) { Write-Error "VM not ready."; exit 1 }

Write-Host "Copying driver zip to VM..."
Copy-VMFile -Name $VMName -SourcePath $zipPath -DestinationPath "C:\NvGpuP_HS.zip" `
    -CreateFullPath -FileSource Host -Force
Write-Host "  Copied."
Remove-Item $zipPath -Force

# =============================================================================
# In VM: remove oem4.inf wrapper (cleanup), populate HostDriverStore
# =============================================================================
$session = New-PSSession -VMName $VMName -Credential $VMCred

Invoke-Command -Session $session -ScriptBlock {
    param($folderName)

    # -------------------------------------------------------------------------
    # Remove failed wrapper driver (oem4.inf) if present
    # -------------------------------------------------------------------------
    Write-Host "=== Cleaning up wrapper INF ===" -ForegroundColor Cyan
    $oem4 = "C:\Windows\INF\oem4.inf"
    if (Test-Path $oem4) {
        Write-Host "  Removing oem4.inf (failed wrapper)..."
        pnputil /delete-driver oem4.inf /uninstall /force 2>&1 | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "  oem4.inf not present, skipping."
    }

    # -------------------------------------------------------------------------
    # Extract and copy to HostDriverStore
    # -------------------------------------------------------------------------
    Write-Host ""
    Write-Host "=== Extracting driver archive ===" -ForegroundColor Cyan
    $extractDir = "C:\NvGpuP_HS_Extract"
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
    Expand-Archive "C:\NvGpuP_HS.zip" $extractDir -Force
    Remove-Item "C:\NvGpuP_HS.zip" -Force

    Write-Host ""
    Write-Host "=== Copying to HostDriverStore ===" -ForegroundColor Cyan
    $hds = "C:\Windows\System32\HostDriverStore\FileRepository\$folderName"
    New-Item -ItemType Directory -Force -Path $hds | Out-Null
    Copy-Item "$extractDir\DriverStore\$folderName\*" $hds -Recurse -Force
    Write-Host "  HostDriverStore populated: $hds"

    Write-Host ""
    Write-Host "=== Copying System32 DLLs ===" -ForegroundColor Cyan
    $dllCount = 0
    Get-ChildItem "$extractDir\System32" | ForEach-Object {
        Copy-Item $_.FullName "C:\Windows\System32\$($_.Name)" -Force
        $dllCount++
    }
    Write-Host "  Copied $dllCount DLLs to System32."

    Remove-Item $extractDir -Recurse -Force

    # -------------------------------------------------------------------------
    # Show current device state
    # -------------------------------------------------------------------------
    Write-Host ""
    Write-Host "=== GPU-P device state ===" -ForegroundColor Cyan
    Get-PnpDevice | Where-Object { $_.InstanceId -like "*VEN_1414*" } |
        Format-Table FriendlyName, Status, InstanceId -AutoSize

    Write-Host ""
    Write-Host "=== HostDriverStore content ===" -ForegroundColor Cyan
    $hdsRoot = "C:\Windows\System32\HostDriverStore\FileRepository"
    if (Test-Path $hdsRoot) {
        Get-ChildItem $hdsRoot | ForEach-Object { Write-Host "  $($_.Name)" }
    } else {
        Write-Host "  HostDriverStore not found!" -ForegroundColor Red
    }

} -ArgumentList $nvFolder.Name

Remove-PSSession $session

Write-Host ""
Write-Host "Rebooting VM..." -ForegroundColor Cyan
Restart-VM -Name $VMName -Force
Write-Host "Done. After reboot (~30s), check Parsec/Device Manager for the GPU." -ForegroundColor Green
