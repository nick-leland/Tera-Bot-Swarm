#Requires -RunAsAdministrator
# =============================================================================
# 13_clean-custom-drivers.ps1
# Remove our broken test-signed OEM packages from TeraBot1.
# Let the inbox vrd.inf (Microsoft-signed) be the driver for the GPU-P device.
# =============================================================================
. "$PSScriptRoot\config.ps1"

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {

    Write-Host "=== Current staged OEM drivers ===" -ForegroundColor Cyan
    pnputil /enum-drivers | Select-String "Published|Original|DriverVer|Signer" | ForEach-Object { $_.Line }

    Write-Host ""
    Write-Host "=== Removing custom vrd packages (oem2, oem4, oem5) ===" -ForegroundColor Cyan
    # Find all oem*.inf that are vrd-related or NVIDIA-related (our broken ones)
    $oemInfs = pnputil /enum-drivers 2>&1 | Select-String "Published Name.*oem" | ForEach-Object {
        if ($_ -match "oem(\d+)\.inf") { "oem$($matches[1]).inf" }
    }

    foreach ($oem in $oemInfs) {
        $infPath = "C:\Windows\INF\$oem"
        if (Test-Path $infPath) {
            $content = Get-Content $infPath -ErrorAction SilentlyContinue
            # Remove if it's one of our custom VRD or NVIDIA display driver packages
            $isCustom = $content -match "VrdGpuP|VirtualRenderDisk" -or
                        ($content -match "Display" -and $content -match "NVIDIA" -and $content -match "oem")
            if ($isCustom) {
                Write-Host "  Removing $oem (custom vrd/NVIDIA package)..." -ForegroundColor Yellow
                pnputil /delete-driver $oem /uninstall /force 2>&1 | Write-Host
            } else {
                Write-Host "  Keeping $oem" -ForegroundColor DarkGray
            }
        }
    }

    Write-Host ""
    Write-Host "=== Also force-remove oem2, oem4, oem5 by name ===" -ForegroundColor Cyan
    foreach ($name in @("oem2.inf", "oem4.inf", "oem5.inf")) {
        $result = pnputil /delete-driver $name /uninstall /force 2>&1
        Write-Host "  $name : $($result -join ' ')"
    }

    Write-Host ""
    Write-Host "=== vrd DriverStore folders remaining ===" -ForegroundColor Cyan
    Get-ChildItem "C:\Windows\System32\DriverStore\FileRepository" -Filter "vrd.inf_*" | ForEach-Object {
        $sys = "$($_.FullName)\vrd.sys"
        $ver = if (Test-Path $sys) { (Get-Item $sys).VersionInfo.FileVersion } else { "no sys" }
        Write-Host "  $($_.Name): vrd.sys $ver"
    }

    Write-Host ""
    Write-Host "=== GPU-P device state ===" -ForegroundColor Cyan
    Get-PnpDevice | Where-Object { $_.InstanceId -like "*VEN_1414*" } |
        Format-Table FriendlyName, Status, InstanceId -AutoSize

    Write-Host ""
    Write-Host "=== HostDriverStore ===" -ForegroundColor Cyan
    $hds = "C:\Windows\System32\HostDriverStore\FileRepository"
    if (Test-Path $hds) {
        Get-ChildItem $hds | Format-Table Name
    } else {
        Write-Host "  NOT FOUND" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Restoring driversipolicy.p7b (offline - needed for inbox driver) ===" -ForegroundColor Cyan
$osDisk = (Get-VMHardDiskDrive -VMName $VMName | Where-Object { $_.ControllerLocation -eq 0 }).Path
Write-Host "  (Will restore offline after reboot for safety)"
# Note: driversipolicy.p7b was renamed to .bak but since TeraGPU works WITH it, restore it
# We'll do this inline here by connecting to the VM while running
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $ci = "C:\Windows\System32\CodeIntegrity"
    $bak = "$ci\driversipolicy.p7b.bak"
    $orig = "$ci\driversipolicy.p7b"
    if ((Test-Path $bak) -and !(Test-Path $orig)) {
        # Need to take ownership / bypass TrustedInstaller
        $result = cmd /c "takeown /f `"$bak`" /a" 2>&1
        $result2 = cmd /c "icacls `"$bak`" /grant administrators:F" 2>&1
        Rename-Item $bak $orig -Force -ErrorAction SilentlyContinue
        if (Test-Path $orig) {
            Write-Host "  driversipolicy.p7b restored." -ForegroundColor Green
        } else {
            Write-Host "  Could not restore (will do offline)" -ForegroundColor Yellow
        }
    } elseif (Test-Path $orig) {
        Write-Host "  driversipolicy.p7b already present." -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "=== Rebooting VM ===" -ForegroundColor Cyan
Restart-VM -Name $VMName -Force
Start-Sleep 20

$timeout = 120; $elapsed = 0
while ($elapsed -lt $timeout) {
    try {
        Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { 1 } -ErrorAction Stop | Out-Null
        Write-Host "VM ready." -ForegroundColor Green
        break
    } catch { Start-Sleep 10; $elapsed += 10; Write-Host "  $elapsed s..." }
}

Write-Host ""
Write-Host "=== Post-reboot device state ===" -ForegroundColor Cyan
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Get-PnpDevice | Where-Object { $_.InstanceId -like "*VEN_1414*" -or $_.Class -eq "Display" } |
        Format-Table FriendlyName, Status, InstanceId -AutoSize

    Write-Host ""
    $dev = Get-WmiObject Win32_PnPEntity | Where-Object { $_.DeviceID -like "*VEN_1414*DEV_008E*" } | Select-Object -First 1
    if ($dev) { Write-Host "ConfigManagerErrorCode: $($dev.ConfigManagerErrorCode)" }

    Write-Host ""
    Write-Host "=== Display adapters ===" -ForegroundColor Cyan
    Get-WmiObject Win32_VideoController | Format-Table Name, Status -AutoSize

    Write-Host ""
    Write-Host "=== CI events (last 5) ===" -ForegroundColor Cyan
    Get-WinEvent -LogName "Microsoft-Windows-CodeIntegrity/Operational" -MaxEvents 5 -ErrorAction SilentlyContinue |
        Format-Table TimeCreated, Id, Message -Wrap
}
