## Install patched NVIDIA driver via pnputil using a temp staging folder.
## pnputil stages files to DriverStore itself - we just provide the source.

$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

# Patch the host INF
$hostInfPath = 'C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_4bf4c17fa8a478b5\nv_dispi.inf'
Write-Host 'Reading and patching host INF...'
$infText = [System.IO.File]::ReadAllText($hostInfPath, [System.Text.Encoding]::UTF8)

$oldDevLine = '%NVIDIA_DEV.2B85%           = Section048, PCI\VEN_10DE&DEV_2B85                 '
$newDevLines = $oldDevLine + "`r`n" + '%NVIDIA_DEV.2B85.GPU-P%    = Section048, PCI\VEN_1414&DEV_008E              '
$infText = $infText.Replace($oldDevLine, $newDevLines)

$oldStr = 'NVIDIA_DEV.2B85 = "NVIDIA GeForce RTX 5090"'
$newStr = $oldStr + "`r`n" + 'NVIDIA_DEV.2B85.GPU-P = "NVIDIA GeForce RTX 5090 (GPU-P)"'
$infText = $infText.Replace($oldStr, $newStr)

if ($infText -notlike '*VEN_1414*') { Write-Error 'Patch failed'; exit 1 }
Write-Host 'INF patched. VEN_1414 confirmed.'

# Compress for transfer
$bytes = [System.Text.Encoding]::UTF8.GetBytes($infText)
$ms = New-Object System.IO.MemoryStream
$gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Compress)
$gz.Write($bytes, 0, $bytes.Length)
$gz.Close()
$compressedB64 = [Convert]::ToBase64String($ms.ToArray())
Write-Host "Compressed INF: $($compressedB64.Length) chars"

Invoke-Command -VMName $VMName -Credential $VMCred -ArgumentList $compressedB64 -ScriptBlock {
    param($infB64)

    $srcStore = 'C:\Windows\System32\HostDriverStore\FileRepository\nv_dispi.inf_amd64_6d8eaa80a18aada4'
    $tmpDir = 'C:\Windows\Temp\nvidia-drv'

    # Decompress INF
    $compressed = [Convert]::FromBase64String($infB64)
    $ms = New-Object System.IO.MemoryStream(,$compressed)
    $gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
    $outMs = New-Object System.IO.MemoryStream
    $gz.CopyTo($outMs)
    $infText = [System.Text.Encoding]::UTF8.GetString($outMs.ToArray())
    Write-Host "INF received: $($infText.Length) chars, VEN_1414 present: $($infText -like '*VEN_1414*')"

    # Create temp dir
    if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    Write-Host "Created temp dir: $tmpDir"

    # Copy ALL files from HostDriverStore to temp dir
    Write-Host 'Copying driver files...'
    $files = Get-ChildItem $srcStore -ErrorAction SilentlyContinue
    $count = 0; $errors = 0
    foreach ($f in $files) {
        $dst = Join-Path $tmpDir $f.Name
        try {
            [System.IO.File]::Copy($f.FullName, $dst, $true)
            $count++
        } catch {
            $errors++
        }
    }
    Write-Host "Copied: $count files, Errors: $errors"

    # Write patched INF (override the INF that was copied from HostDriverStore)
    $infDst = Join-Path $tmpDir 'nv_dispi.inf'
    [System.IO.File]::WriteAllText($infDst, $infText, [System.Text.Encoding]::UTF8)
    Write-Host "Written patched INF: $infDst"

    # Verify key files
    Write-Host '=== Key files in temp dir ==='
    foreach ($f in @('nv_dispi.inf', 'NV_DISP.CAT', 'nvlddmkm.sys', 'nvwgf2umx.dll', 'nvldumdx.dll')) {
        $p = Join-Path $tmpDir $f
        if (Test-Path $p) {
            $sz = [math]::Round((Get-Item $p).Length / 1MB, 1)
            Write-Host "  OK: $f ($sz MB)"
        } else { Write-Host "  MISSING: $f" }
    }

    # Run pnputil
    Write-Host '=== pnputil /add-driver /install ==='
    $result = pnputil /add-driver $infDst /install 2>&1
    Write-Host $result

    Write-Host '=== NVIDIA device status ==='
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA*' } | Select-Object Status, FriendlyName

    Write-Host '=== GPU adapter registry after pnputil ==='
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($p.DriverDesc -and ($p.ProviderName -like '*NVIDIA*' -or $p.DriverDesc -like '*Virtual Render*' -or $p.DriverDesc -like '*NVIDIA*')) {
                $umd = if ($p.UserModeDriverName) { $p.UserModeDriverName[0] } else { '(none)' }
                Write-Host "  $($p.DriverDesc) | UMD: $umd | Ver: $($p.DriverVersion)"
            }
        }
}
