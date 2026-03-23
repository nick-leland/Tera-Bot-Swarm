$osDisk = "C:\VirtualMachines\Virtual Hard Disks\TeraGPU.vhdx"

Write-Host "Mounting TeraGPU VHDX offline..."
$disk = Mount-VHD -Path $osDisk -ReadOnly -PassThru | Get-Disk
$winPart = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Size -gt 20GB } | Select-Object -First 1
Set-Partition -DiskNumber $disk.Number -PartitionNumber $winPart.PartitionNumber -NewDriveLetter Y

Write-Host ""
Write-Host "=== HostDriverStore folders + content ===" -ForegroundColor Cyan
$hds = "Y:\Windows\System32\HostDriverStore\FileRepository"
$folders = Get-ChildItem $hds
foreach ($f in $folders) {
    Write-Host "  Folder: $($f.Name)"
    $inf = Get-ChildItem $f.FullName -Filter "*.inf" | Select-Object -First 1
    if ($inf) {
        $driverVer = Get-Content $inf.FullName | Select-String "DriverVer" | Select-Object -First 1
        $provider  = Get-Content $inf.FullName | Select-String "Provider\s*=" | Select-Object -First 1
        Write-Host "    INF: $($inf.Name) | $driverVer | $provider"
    }
    $fileCount = (Get-ChildItem $f.FullName -Recurse -File).Count
    $folderSize = [Math]::Round((Get-ChildItem $f.FullName -Recurse -File | Measure-Object Length -Sum).Sum / 1MB, 1)
    Write-Host "    Files: $fileCount, Size: $folderSize MB"
}

Write-Host ""
Write-Host "=== OEM display INFs ===" -ForegroundColor Cyan
Get-ChildItem "Y:\Windows\INF" -Filter "oem*.inf" | ForEach-Object {
    $lines = Get-Content $_.FullName -TotalCount 5 -ErrorAction SilentlyContinue
    if ($lines -match "NVIDIA|Display|VEN_1414") {
        Write-Host "  $($_.Name):"
        $lines | ForEach-Object { Write-Host "    $_" }
    }
}

Remove-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $winPart.PartitionNumber -AccessPath "Y:\"
Dismount-VHD -Path $osDisk
Write-Host "Unmounted."
