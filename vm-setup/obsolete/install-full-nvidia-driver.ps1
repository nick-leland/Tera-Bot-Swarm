## Full NVIDIA GPU-P driver installation for TeraBot1 VM.
## nointegritychecks + testsigning already on, so no signature issues.
## Steps:
##   1. Patch host 4bf4c17 INF to add VEN_1414&DEV_008E
##   2. Transfer patched INF to VM
##   3. VM: copy HostDriverStore files to DriverStore location
##   4. Run pnputil /add-driver
##   5. Reboot VM

$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

# --- Step 1: Patch the host INF ---
$hostInfPath = 'C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_4bf4c17fa8a478b5\nv_dispi.inf'
Write-Host 'Reading host INF...'
$infText = [System.IO.File]::ReadAllText($hostInfPath, [System.Text.Encoding]::UTF8)

# Add VEN_1414 device entry after the VEN_10DE&DEV_2B85 line
$oldDevLine = '%NVIDIA_DEV.2B85%           = Section048, PCI\VEN_10DE&DEV_2B85                 '
$newDevLines = $oldDevLine + "`r`n" + '%NVIDIA_DEV.2B85.GPU-P%    = Section048, PCI\VEN_1414&DEV_008E              '
if ($infText -like "*$oldDevLine*") {
    $infText = $infText.Replace($oldDevLine, $newDevLines)
    Write-Host 'Patched: added VEN_1414 device entry'
} else {
    Write-Error 'Could not find DEV_2B85 device line in INF'
    exit 1
}

# Add string for new device
$oldStr = 'NVIDIA_DEV.2B85 = "NVIDIA GeForce RTX 5090"'
$newStr = $oldStr + "`r`n" + 'NVIDIA_DEV.2B85.GPU-P = "NVIDIA GeForce RTX 5090 (GPU-P)"'
if ($infText -like "*$oldStr*") {
    $infText = $infText.Replace($oldStr, $newStr)
    Write-Host 'Patched: added GPU-P string'
} else {
    Write-Error 'Could not find NVIDIA_DEV.2B85 string in INF'
    exit 1
}

Write-Host 'INF patched successfully'

# Compress INF text for transfer
$bytes = [System.Text.Encoding]::UTF8.GetBytes($infText)
$ms = New-Object System.IO.MemoryStream
$gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Compress)
$gz.Write($bytes, 0, $bytes.Length)
$gz.Close()
$compressedB64 = [Convert]::ToBase64String($ms.ToArray())
Write-Host "INF size: $($bytes.Length) bytes, compressed+b64: $($compressedB64.Length) chars"

# --- Step 2 & 3 & 4: Transfer INF to VM, copy files, run pnputil ---
Write-Host 'Connecting to VM...'
Invoke-Command -VMName $VMName -Credential $VMCred -ArgumentList $compressedB64 -ScriptBlock {
    param($infB64)

    $targetFolder = 'C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_4bf4c17fa8a478b5'
    $hostStoreFolder = 'C:\Windows\System32\HostDriverStore\FileRepository\nv_dispi.inf_amd64_6d8eaa80a18aada4'

    # Decompress INF
    $compressed = [Convert]::FromBase64String($infB64)
    $ms = New-Object System.IO.MemoryStream(,$compressed)
    $gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
    $outMs = New-Object System.IO.MemoryStream
    $gz.CopyTo($outMs)
    $infText = [System.Text.Encoding]::UTF8.GetString($outMs.ToArray())
    Write-Host "INF received: $($infText.Length) chars"

    # Verify VEN_1414 is in the patched INF
    if ($infText -like '*VEN_1414*') {
        Write-Host 'VEN_1414 confirmed in patched INF'
    } else {
        Write-Host 'ERROR: VEN_1414 not found in received INF'
        exit 1
    }

    # Create target DriverStore folder
    New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
    Write-Host "Created: $targetFolder"

    # Copy ALL files from HostDriverStore to DriverStore (within VM - fast internal copy)
    Write-Host 'Copying driver files from HostDriverStore to DriverStore...'
    $files = Get-ChildItem $hostStoreFolder -ErrorAction SilentlyContinue
    $count = 0
    foreach ($f in $files) {
        $dst = Join-Path $targetFolder $f.Name
        try {
            [System.IO.File]::Copy($f.FullName, $dst, $true)
            $count++
        } catch {
            # Skip locked/inaccessible files
        }
    }
    Write-Host "Copied $count files"

    # Write patched INF to the target folder (overwrites the old nv_dispi.inf)
    $infDst = Join-Path $targetFolder 'nv_dispi.inf'
    [System.IO.File]::WriteAllText($infDst, $infText, [System.Text.Encoding]::UTF8)
    Write-Host "Written patched nv_dispi.inf to $infDst"

    # Also need a catalog file - copy the existing NV_DISP.CAT (will fail catalog check but nointegritychecks bypasses it)
    $catSrc = Join-Path $hostStoreFolder 'NV_DISP.CAT'
    $catDst = Join-Path $targetFolder 'NV_DISP.CAT'
    if (Test-Path $catSrc) {
        [System.IO.File]::Copy($catSrc, $catDst, $true)
        Write-Host 'Copied NV_DISP.CAT'
    }

    # Verify key files
    Write-Host '=== Key files in target folder ==='
    foreach ($f in @('nv_dispi.inf', 'NV_DISP.CAT', 'nvlddmkm.sys', 'nvwgf2umx.dll', 'nvldumdx.dll')) {
        $p = Join-Path $targetFolder $f
        if (Test-Path $p) {
            $sz = [math]::Round((Get-Item $p).Length / 1MB, 1)
            Write-Host "  OK: $f ($sz MB)"
        } else { Write-Host "  MISSING: $f" }
    }

    # Run pnputil to install the driver
    Write-Host '=== Running pnputil /add-driver ==='
    $infPath = Join-Path $targetFolder 'nv_dispi.inf'
    $result = pnputil /add-driver $infPath /install 2>&1
    Write-Host $result

    Write-Host '=== pnputil result ==='
    if ($result -like '*success*' -or $result -like '*0 error*' -or $result -like '*Driver package added successfully*') {
        Write-Host 'SUCCESS: Driver installed via pnputil'
    } elseif ($result -like '*error*' -or $result -like '*failed*') {
        Write-Host 'ERROR or WARNING from pnputil - check output above'
    }

    # Check if VEN_1414 device driver changed
    Write-Host '=== NVIDIA PnP device after install ==='
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA*' -or $_.InstanceId -like '*VEN_1414*' } |
        Select-Object Status, FriendlyName, InstanceId | Format-List
}

Write-Host ''
Write-Host 'Rebooting VM in 5 seconds...'
Start-Sleep -Seconds 5

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Restart-Computer -Force
} -ErrorAction SilentlyContinue

Write-Host 'VM rebooting. Waiting for it to come back (up to 3 min)...'
Start-Sleep -Seconds 20
for ($i = 0; $i -lt 18; $i++) {
    Start-Sleep -Seconds 10
    try {
        $r = Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { 'ok' } -ErrorAction Stop
        if ($r -eq 'ok') { Write-Host 'VM is back online.'; break }
    } catch { Write-Host "  Waiting... ($($i*10+20)s)" }
}

Write-Host 'Waiting 60s for boot tasks + logon + Parsec...'
Start-Sleep -Seconds 60

# Final check
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host '=== NVIDIA device after reboot ==='
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA*' -or $_.InstanceId -like '*VEN_1414*' } |
        Select-Object Status, FriendlyName | Format-Table -AutoSize

    Write-Host '=== Display adapters ==='
    Get-PnpDevice | Where-Object { $_.Class -eq 'Display' } | Select-Object Status, FriendlyName | Format-Table -AutoSize

    Write-Host '=== GPU adapter registry (UMD + WddmVersion) ==='
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($p.DriverDesc) {
                $umd = if ($p.UserModeDriverName) { $p.UserModeDriverName[0] } else { '(none)' }
                Write-Host "  $($p.DriverDesc)"
                Write-Host "    UMD: $umd"
                Write-Host "    WddmVersion: $($p.WddmVersion)"
                Write-Host "    DriverVersion: $($p.DriverVersion)"
            }
        }

    Write-Host '=== Parsec processes ==='
    Get-WmiObject Win32_Process | Where-Object { $_.Name -like 'parsec*' } |
        Select-Object Name, ProcessId, SessionId | Format-Table -AutoSize
}
