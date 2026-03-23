$VMName = 'TeraBot1'
$GPUName = 'NVIDIA GeForce RTX 5090'

# Stop VM
Write-Host "Stopping $VMName..."
$vm = Get-VM -Name $VMName
$wasRunning = ($vm.State -eq 'Running')
if ($vm.State -ne 'Off') {
    Stop-VM -Name $VMName -Force
    $timeout = 60
    while ((Get-VM -Name $VMName).State -ne 'Off' -and $timeout -gt 0) {
        Start-Sleep -Seconds 3; $timeout -= 3
        Write-Host "  Waiting for VM to stop ($timeout s)..."
    }
}
Write-Host "VM is Off."

# Mount VHD
$vhd = Get-VHD -VMId (Get-VM -Name $VMName).VMId
Write-Host "Mounting VHD: $($vhd.Path)"
$disk = Mount-VHD -Path $vhd.Path -PassThru | Get-Disk
$vol = $disk | Get-Partition | Get-Volume | Where-Object { $_.DriveLetter -and $_.FileSystem -eq 'NTFS' } | Sort-Object Size -Descending | Select-Object -First 1
$D = $vol.DriveLetter
Write-Host "VM drive mounted as $D`:"

# Get active NVIDIA driver info from host
Write-Host "Getting NVIDIA driver info from host..."
$driver = Get-WmiObject Win32_PNPSignedDriver | Where-Object { $_.DeviceName -eq $GPUName } | Select-Object -First 1
if (!$driver) { Write-Error "NVIDIA driver not found on host"; Dismount-VHD -Path $vhd.Path; exit 1 }
Write-Host "Driver: $($driver.DriverVersion) / InfName: $($driver.InfName)"

# Get GPU service name (nvlddmkm) and its path
$gpuDevice = Get-PnpDevice | Where-Object { $_.Name -eq $GPUName -and $_.Status -eq 'OK' } | Select-Object -First 1
$gpuServiceName = $gpuDevice.Service
Write-Host "GPU Service: $gpuServiceName"
$svcDriver = Get-WmiObject Win32_SystemDriver | Where-Object { $_.Name -eq $gpuServiceName }
if ($svcDriver) {
    $servicePath = $svcDriver.Pathname
    $serviceDriverDir = $servicePath.Split('\')[0..5] -join '\'
    $serviceDest = "$D`:\Windows\System32\HostDriverStore\FileRepository\" + ($servicePath.Split('\')[3..5] -join '\')
    Write-Host "Copying service driver: $serviceDriverDir -> $(Split-Path $serviceDest)"
    New-Item -ItemType Directory -Path (Split-Path $serviceDest) -Force | Out-Null
    if (!(Test-Path $serviceDest)) {
        Copy-Item -Path $serviceDriverDir -Destination (Split-Path $serviceDest) -Recurse -Force
        Write-Host "  Copied."
    } else { Write-Host "  Already exists, skipping." }
}

# Get all driver files via CIMDataFile
$modID = $driver.DeviceID -replace '\\', '\\'
$antecedent = "\\$env:COMPUTERNAME\ROOT\cimv2:Win32_PNPSignedDriver.DeviceID=""$modID"""
$driverFiles = Get-WmiObject Win32_PNPSignedDriverCIMDataFile | Where-Object { $_.Antecedent -eq $antecedent }
Write-Host "Found $($driverFiles.Count) driver files to copy..."

$copied = 0; $skipped = 0
foreach ($f in $driverFiles) {
    $path = ($f.Dependent.Split("=")[1] -replace '\\\\', '\').Trim('"')
    if (!(Test-Path $path)) { continue }

    if ($path -like "C:\Windows\System32\DriverStore\*") {
        # Copy entire INF folder to HostDriverStore in VM
        $driverDir = $path.Split('\')[0..5] -join '\'
        $driverDest = "$D`:\Windows\System32\HostDriverStore\FileRepository\" + $($path.Split('\')[5])
        if (!(Test-Path $driverDest)) {
            New-Item -ItemType Directory -Path "$D`:\Windows\System32\HostDriverStore\FileRepository" -Force | Out-Null
            Copy-Item -Path $driverDir -Destination "$D`:\Windows\System32\HostDriverStore\FileRepository\" -Recurse -Force
            $copied++
            Write-Host "  Copied DriverStore folder: $($path.Split('\')[5])"
        } else { $skipped++ }
    } else {
        # Copy System32 DLLs, SYS files, etc.
        $destPath = $path.Replace("C:\", "$D`:\")
        $destDir = Split-Path $destPath
        if (!(Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        if (!(Test-Path $destPath)) {
            Copy-Item -Path $path -Destination $destDir -Force
            $copied++
        } else { $skipped++ }
    }
}
Write-Host "Copy complete: $copied copied, $skipped skipped."

# Dismount
Write-Host "Dismounting VHD..."
Dismount-VHD -Path $vhd.Path
Write-Host "VHD dismounted."

# Start VM
if ($wasRunning) {
    Write-Host "Starting $VMName..."
    Start-VM -Name $VMName
    Write-Host "VM started. Wait ~90s then check if NVIDIA shows in Task Manager."
}
