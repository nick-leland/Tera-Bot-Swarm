## Copy NVIDIA 4bf4c17 driver files from host to VM using Hyper-V Guest Services.
## Then patch INF and run pnputil to install full NVIDIA driver for GPU-P.

$VMName = 'TeraBot1'
$srcDir = 'C:\Temp\nv-driver-4bf4c17'
$vmTmpDir = 'C:\Windows\Temp\nvidia-drv-new'

Write-Host "Copying $((Get-ChildItem $srcDir).Count) files to VM via Guest Services..."
$files = Get-ChildItem $srcDir
$i = 0
foreach ($f in $files) {
    $vmDst = "$vmTmpDir\$($f.Name)"
    try {
        Copy-VMFile -VMName $VMName -SourcePath $f.FullName -DestinationPath $vmDst -CreateFullPath -FileSource Host -Force
        $i++
        if ($i % 20 -eq 0) { Write-Host "  Copied $i / $($files.Count)..." }
    } catch {
        Write-Host "  WARN: $($f.Name) - $($_.Exception.Message)"
    }
}
Write-Host "Done. Copied $i files."
