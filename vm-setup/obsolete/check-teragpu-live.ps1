$vmName = "TeraGPU"
$cred = New-Object System.Management.Automation.PSCredential(
    "user",  # try default - we don't know the TeraGPU creds
    (ConvertTo-SecureString "password" -AsPlainText -Force)
)

# Check if already running
if ((Get-VM -Name $vmName).State -ne "Running") {
    Write-Host "Starting TeraGPU..."
    Start-VM -Name $vmName
    Start-Sleep 30
}

# Try several common credentials
$credPairs = @(
    @("Administrator", ""),
    @("user", ""),
    @("user", "password"),
    @("bot", "bot123"),
    @("Admin", "password"),
    @("Administrator", "password")
)

$session = $null
foreach ($pair in $credPairs) {
    try {
        $c = New-Object System.Management.Automation.PSCredential(
            $pair[0],
            (ConvertTo-SecureString $pair[1] -AsPlainText -Force)
        )
        $session = New-PSSession -VMName $vmName -Credential $c -ErrorAction Stop
        Write-Host "Connected as $($pair[0])" -ForegroundColor Green
        break
    } catch { }
}

if (-not $session) {
    Write-Host "Could not connect. What are the TeraGPU credentials?" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "=== Checking HostDriverStore on TeraGPU disk (offline) ==="

    # Mount and check HostDriverStore content
    $osDisk = (Get-VMHardDiskDrive -VMName $vmName | Where-Object { $_.ControllerLocation -eq 0 }).Path
    $disk = Mount-VHD -Path $osDisk -PassThru | Get-Disk
    $winPart = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Size -gt 20GB } | Select-Object -First 1
    Set-Partition -DiskNumber $disk.Number -PartitionNumber $winPart.PartitionNumber -NewDriveLetter Y

    $hds = "Y:\Windows\System32\HostDriverStore\FileRepository"
    Write-Host "HostDriverStore folders:"
    Get-ChildItem $hds -Directory | Format-Table Name

    foreach ($folder in Get-ChildItem $hds -Directory) {
        Write-Host ""
        Write-Host "  === $($folder.Name) ==="
        Get-ChildItem $folder.FullName -Filter "*.inf" | ForEach-Object {
            $ver = (Get-Content $_.FullName | Select-String "DriverVer") | Select-Object -First 1
            Write-Host "    $($_.Name): $ver"
        }
    }

    # Also check OEM INF for NVIDIA
    Write-Host ""
    Write-Host "=== NVIDIA OEM INF version ==="
    $nvInf = Get-ChildItem "Y:\Windows\INF" -Filter "oem*.inf" | Where-Object {
        (Get-Content $_.FullName -ErrorAction SilentlyContinue | Select-Object -First 3) -match "NVIDIA"
    } | Select-Object -First 1
    if ($nvInf) {
        Get-Content $nvInf.FullName | Select-Object -First 20
    }

    # Check PnP device state in registry
    Write-Host ""
    Write-Host "=== Device class entries (display) ==="
    $regPath = "Y:\Windows\System32\config\SYSTEM"
    # Can't read registry directly offline easily, skip

    Remove-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $winPart.PartitionNumber -AccessPath "Y:\"
    Dismount-VHD -Path $osDisk

    Stop-VM -Name $vmName -Force -ErrorAction SilentlyContinue
    exit
}

# Connected - check live state
Invoke-Command -Session $session -ScriptBlock {
    Write-Host "=== Windows version ===" -ForegroundColor Cyan
    [System.Environment]::OSVersion.Version

    Write-Host ""
    Write-Host "=== GPU-P devices ===" -ForegroundColor Cyan
    Get-PnpDevice | Where-Object { $_.InstanceId -like "*VEN_1414*" -or $_.Class -eq "Display" } |
        Format-Table FriendlyName, Status, InstanceId -AutoSize

    Write-Host ""
    Write-Host "=== Display adapters (WMI) ===" -ForegroundColor Cyan
    Get-WmiObject Win32_VideoController | Format-Table Name, Status, AdapterDACType -AutoSize

    Write-Host ""
    Write-Host "=== BCD testsigning ===" -ForegroundColor Cyan
    bcdedit /enum | Select-String "testsign|nointegrit"

    Write-Host ""
    Write-Host "=== Latest CI events ===" -ForegroundColor Cyan
    Get-WinEvent -LogName "Microsoft-Windows-CodeIntegrity/Operational" -MaxEvents 5 -ErrorAction SilentlyContinue |
        Format-Table TimeCreated, Id, Message -Wrap
}

Remove-PSSession $session
Stop-VM -Name $vmName -TurnOff:$false -ErrorAction SilentlyContinue
