$vmName = "TeraGPU"

Write-Host "=== TeraGPU firmware ===" -ForegroundColor Cyan
Get-VMFirmware -VMName $vmName | Select-Object SecureBoot, SecureBootTemplate | Format-List

Write-Host "=== GPU Partition Adapter ===" -ForegroundColor Cyan
Get-VMGpuPartitionAdapter -VMName $vmName -ErrorAction SilentlyContinue | Format-List

Write-Host "=== VM Specs ===" -ForegroundColor Cyan
Get-VM -Name $vmName | Select-Object Generation, ProcessorCount, MemoryStartupBytes | Format-List

Write-Host "=== Disks ===" -ForegroundColor Cyan
Get-VMHardDiskDrive -VMName $vmName | Format-Table ControllerLocation, Path

Write-Host "=== Disk Details ===" -ForegroundColor Cyan
Get-VMHardDiskDrive -VMName $vmName | ForEach-Object {
    $p = $_.Path
    $vhd = Get-VHD -Path $p -ErrorAction SilentlyContinue
    Write-Host "  Loc $($_.ControllerLocation): $p"
    if ($vhd) {
        Write-Host "    Type=$($vhd.VhdType) Size=$([Math]::Round($vhd.FileSize/1GB,1))GB"
        if ($vhd.VhdType -eq 'Differencing') { Write-Host "    Parent=$($vhd.ParentPath)" }
    }
}

# Mount the OS disk offline to check key files
Write-Host ""
Write-Host "=== Mounting TeraGPU OS disk offline ===" -ForegroundColor Cyan
$osDisk = (Get-VMHardDiskDrive -VMName $vmName | Where-Object { $_.ControllerLocation -eq 0 }).Path
Write-Host "  Disk: $osDisk"
$disk = Mount-VHD -Path $osDisk -PassThru | Get-Disk
$winPart = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Size -gt 20GB } | Select-Object -First 1
$efiPart = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Size -lt 200MB -and $_.Size -gt 50MB } | Select-Object -First 1

if ($winPart) {
    Set-Partition -DiskNumber $disk.Number -PartitionNumber $winPart.PartitionNumber -NewDriveLetter Y
    Write-Host "  Windows at Y:"

    Write-Host ""
    Write-Host "=== Windows version ===" -ForegroundColor Cyan
    (Get-Item "Y:\Windows\System32\ntoskrnl.exe").VersionInfo | Select-Object ProductVersion, FileVersion | Format-List

    Write-Host ""
    Write-Host "=== CI policy files ===" -ForegroundColor Cyan
    Get-ChildItem "Y:\Windows\System32\CodeIntegrity" -ErrorAction SilentlyContinue | Format-Table Name, Length

    Write-Host ""
    Write-Host "=== vrd DriverStore folders ===" -ForegroundColor Cyan
    Get-ChildItem "Y:\Windows\System32\DriverStore\FileRepository" -Filter "vrd.inf_*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $sys = "$($_.FullName)\vrd.sys"
        $ver = if (Test-Path $sys) { (Get-Item $sys).VersionInfo.FileVersion } else { "no sys" }
        Write-Host "  $($_.Name): vrd.sys $ver"
    }

    Write-Host ""
    Write-Host "=== HostDriverStore ===" -ForegroundColor Cyan
    $hds = "Y:\Windows\System32\HostDriverStore\FileRepository"
    if (Test-Path $hds) {
        Get-ChildItem $hds -Directory | Select-Object Name | Format-Table
    } else { Write-Host "  Not found" }

    Write-Host ""
    Write-Host "=== OEM INFs (display class) ===" -ForegroundColor Cyan
    Get-ChildItem "Y:\Windows\INF" -Filter "oem*.inf" | ForEach-Object {
        $head = Get-Content $_.FullName -ErrorAction SilentlyContinue | Select-Object -First 5
        if ($head -match "Display|VEN_1414|vrd|NVIDIA") {
            Write-Host "  $($_.Name):"
            $head | ForEach-Object { Write-Host "    $_" }
        }
    }

    Remove-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $winPart.PartitionNumber -AccessPath "Y:\"
}

if ($efiPart) {
    Set-Partition -DiskNumber $disk.Number -PartitionNumber $efiPart.PartitionNumber -NewDriveLetter Z
    Write-Host ""
    Write-Host "=== BCD (EFI) ===" -ForegroundColor Cyan
    bcdedit /store "Z:\EFI\Microsoft\Boot\BCD" /enum | Select-String "testsign|nointegrit|identifier|description"
    Remove-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $efiPart.PartitionNumber -AccessPath "Z:\"
}

Dismount-VHD -Path $osDisk
Write-Host ""
Write-Host "Unmounted." -ForegroundColor Green
