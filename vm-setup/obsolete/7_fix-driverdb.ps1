#Requires -RunAsAdministrator
# =============================================================================
# 7_fix-driverdb.ps1 - Add DriverDatabase entry + force driver install on GPU-P
#
# oem4.inf is already staged. Missing piece: DriverDatabase\DeviceIds entry
# for VEN_1414&DEV_008E so Windows knows to use oem4.inf for that device.
# =============================================================================

. "$PSScriptRoot\config.ps1"

Write-Host "Connecting to VM..." -ForegroundColor Cyan
$session = New-PSSession -VMName $VMName -Credential $VMCred -ErrorAction Stop

Invoke-Command -Session $session -ScriptBlock {

    # -------------------------------------------------------------------------
    # Re-apply BCD (recovery restart likely cleared them)
    # -------------------------------------------------------------------------
    Write-Host "=== BCD settings ===" -ForegroundColor Cyan
    bcdedit /set testsigning on       2>&1 | ForEach-Object { Write-Host "  $_" }
    bcdedit /set nointegritychecks on 2>&1 | ForEach-Object { Write-Host "  $_" }
    bcdedit /enum | Select-String "testsigning|nointegrity|loadoption" | ForEach-Object { Write-Host "  $_" }

    # -------------------------------------------------------------------------
    # Find wrapper package in DriverDatabase\DriverPackages
    # -------------------------------------------------------------------------
    Write-Host ""
    Write-Host "=== DriverDatabase packages ===" -ForegroundColor Cyan
    $pkgs = Get-ChildItem "HKLM:\SYSTEM\DriverDatabase\DriverPackages" -ErrorAction SilentlyContinue
    $wrapperPkg = $pkgs | Where-Object { $_.PSChildName -like "*nv_gpup_wrapper*" } | Select-Object -First 1

    if ($wrapperPkg) {
        $pkgKeyName = $wrapperPkg.PSChildName
        Write-Host "  Found wrapper package: $pkgKeyName" -ForegroundColor Green

        # Add DriverDatabase DeviceId mapping
        $tgt = "HKLM:\SYSTEM\DriverDatabase\DeviceIds\PCI\VEN_1414&DEV_008E"
        if (!(Test-Path $tgt)) { New-Item -Path $tgt -Force | Out-Null }
        # Rank 0x0000FFFF = lowest rank (will still be selected if no other driver)
        $rankData = [byte[]](0xFF, 0xFF, 0x00, 0x00)
        New-ItemProperty -Path $tgt -Name $pkgKeyName -Value $rankData -PropertyType Binary -Force | Out-Null
        Write-Host "  DriverDatabase entry added for VEN_1414&DEV_008E." -ForegroundColor Green

        # Trigger device scan
        Write-Host "  Running pnputil /scan-devices..."
        pnputil /scan-devices 2>&1 | Out-Null
        Start-Sleep -Seconds 5

    } else {
        Write-Host "  Wrapper package NOT found. Listing all packages:" -ForegroundColor Yellow
        $pkgs | Select-Object -First 30 | ForEach-Object { Write-Host "    $($_.PSChildName)" }
    }

    # -------------------------------------------------------------------------
    # Force-install driver on the GPU-P device via pnputil /install-device
    # -------------------------------------------------------------------------
    Write-Host ""
    Write-Host "=== GPU-P device state ===" -ForegroundColor Cyan
    $dev = Get-PnpDevice | Where-Object { $_.InstanceId -like "*VEN_1414*DEV_008E*" } | Select-Object -First 1

    if ($dev) {
        Write-Host "  Device: $($dev.InstanceId)"
        Write-Host "  Status: $($dev.Status)  FriendlyName: $($dev.FriendlyName)"
        Write-Host ""
        Write-Host "  Attempting pnputil /install-device..." -ForegroundColor Cyan
        $result = pnputil /install-device $dev.InstanceId 2>&1
        Write-Host ($result -join "`n")
    } else {
        Write-Host "  GPU-P device (VEN_1414&DEV_008E) not found!" -ForegroundColor Red
        Write-Host "  All PnP devices with VEN_1414:"
        Get-PnpDevice | Where-Object { $_.InstanceId -like "*VEN_1414*" } |
            Format-Table FriendlyName, Status, InstanceId -AutoSize
    }

    # -------------------------------------------------------------------------
    # Final state
    # -------------------------------------------------------------------------
    Write-Host ""
    Write-Host "=== All display devices ===" -ForegroundColor Cyan
    Get-PnpDevice -Class Display | Format-Table FriendlyName, Status, InstanceId -AutoSize
}

Remove-PSSession $session

Write-Host ""
Write-Host "Rebooting VM..." -ForegroundColor Cyan
Restart-VM -Name $VMName -Force
Write-Host "Done. Wait ~30s then check Device Manager via Parsec." -ForegroundColor Green
