## Copy NVIDIA driver subdirectory files from host DriverStore to VM.
## Handles Display.NvContainer, NvCamera, NVWMI subdirectories.

$VMName = 'TeraBot1'
$srcDir = 'C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_4bf4c17fa8a478b5'
$vmTmpDir = 'C:\Windows\Temp\nvidia-drv-new'

# Get all files recursively from subdirectories only
$allFiles = Get-ChildItem $srcDir -Recurse | Where-Object { -not $_.PSIsContainer }
$subFiles = $allFiles | Where-Object { $_.FullName -ne (Join-Path $srcDir $_.Name) }

Write-Host "Copying $($subFiles.Count) subdir files to VM..."
$i = 0
foreach ($f in $subFiles) {
    $relPath = $f.FullName.Substring($srcDir.Length + 1)
    $vmDst = "$vmTmpDir\$relPath"
    try {
        Copy-VMFile -VMName $VMName -SourcePath $f.FullName -DestinationPath $vmDst -CreateFullPath -FileSource Host -Force
        $i++
        Write-Host "  OK: $relPath"
    } catch {
        Write-Host "  WARN: $relPath - $($_.Exception.Message)"
    }
}
Write-Host "Done. Copied $i subdir files."
