Stop-VM -Name TeraBot1 -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

$adapter = Get-VMGpuPartitionAdapter -VMName TeraBot1

Set-VMGpuPartitionAdapter -VMName TeraBot1 `
    -MinPartitionVRAM 80000000 `
    -MaxPartitionVRAM 1000000000 `
    -OptimalPartitionVRAM 1000000000 `
    -MinPartitionEncode 80000000 `
    -MaxPartitionEncode 1000000000 `
    -OptimalPartitionEncode 1000000000 `
    -MinPartitionDecode 80000000 `
    -MaxPartitionDecode 1000000000 `
    -OptimalPartitionDecode 1000000000 `
    -MinPartitionCompute 80000000 `
    -MaxPartitionCompute 1000000000 `
    -OptimalPartitionCompute 1000000000

Write-Host "=== New partition ==="
Get-VMGpuPartitionAdapter -VMName TeraBot1 | Select-Object `
    CurrentPartitionVRAM, MinPartitionVRAM, MaxPartitionVRAM, `
    CurrentPartitionCompute, MinPartitionCompute, MaxPartitionCompute

Write-Host "Starting VM..."
Start-VM -Name TeraBot1
Write-Host "Done."
