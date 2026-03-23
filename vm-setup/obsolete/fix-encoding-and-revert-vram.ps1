$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
$hostStore = 'C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_4bf4c17fa8a478b5'

# MFT encoder DLLs to copy
$mftDlls = @(
    'nvEncMFTH264x.dll',
    'nvEncMFThevcx.dll',
    'nvEncMFTav1x.dll',
    'nvDecMFTMjpegx.dll'
)

Write-Host "=== Copying MFT encoder DLLs to VM ==="
foreach ($dll in $mftDlls) {
    $src = Join-Path $hostStore $dll
    $dst = "C:\Windows\System32\$dll"
    if (Test-Path $src) {
        Write-Host "Copying $dll ($([math]::Round((Get-Item $src).Length/1KB,0)) KB)..."
        Copy-VMFile -VMName $VMName -SourcePath $src -DestinationPath $dst `
            -CreateFullPath -FileSource Host -Force
        Write-Host "  OK"
    } else {
        Write-Host "  MISSING on host: $src"
    }
}

Write-Host ""
Write-Host "=== Applying registry fixes in VM ==="
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001'

    # 1. Remove HardwareInformation.qwMemorySize (caused cross-adapter rendering regression)
    Write-Host "[1] Removing HardwareInformation.qwMemorySize..."
    Remove-ItemProperty -Path $classKey -Name 'HardwareInformation.qwMemorySize' -ErrorAction SilentlyContinue
    if ($?) { Write-Host "    Removed." } else { Write-Host "    (already gone)" }

    # 2. Remove GpuPreference for TERA (let it default to adapter 0 = Parsec VDA/WARP for now)
    Write-Host "[2] Removing GpuPreference overrides for TERA..."
    $gpuPrefKey = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    Remove-ItemProperty -Path $gpuPrefKey -Name 'D:\TERA Starscape\Binaries\TERA.exe' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $gpuPrefKey -Name 'D:\TERA Starscape\Tera Starscape Launcher.exe' -ErrorAction SilentlyContinue
    Write-Host "    Done."

    # 3. Register MFT encoder DLLs
    Write-Host "[3] Registering NVIDIA MFT encoders..."

    # H.264 Encoder MFT
    $h264Clsid = '{60F44560-5A20-4857-BFEF-D29773CB8040}'
    $hevcClsid = '{966F107C-8EA2-425D-B822-E4A71BEF01D7}'
    $mjpegClsid = '{70F36578-2741-454F-B494-E8563DDD1CB4}'

    function Register-MFT {
        param($Clsid, $FriendlyName, $DllPath)
        $clsidPath = "HKCR:\CLSID\$Clsid"
        $ipPath = "$clsidPath\InprocServer32"
        if (-not (Test-Path 'HKCR:\')) { New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT | Out-Null }
        if (-not (Test-Path $clsidPath)) { New-Item -Path $clsidPath -Force | Out-Null }
        Set-ItemProperty -Path $clsidPath -Name '(default)' -Value $FriendlyName -Force
        if (-not (Test-Path $ipPath)) { New-Item -Path $ipPath -Force | Out-Null }
        Set-ItemProperty -Path $ipPath -Name '(default)' -Value $DllPath -Force
        Set-ItemProperty -Path $ipPath -Name 'ThreadingModel' -Value 'Both' -Force
        Write-Host "    Registered $FriendlyName"
    }

    Register-MFT $h264Clsid 'NVIDIA H.264 Encoder MFT' 'C:\Windows\System32\nvEncMFTH264x.dll'
    Register-MFT $hevcClsid 'NVIDIA HEVC Encoder MFT' 'C:\Windows\System32\nvEncMFThevcx.dll'
    Register-MFT $mjpegClsid 'NVIDIA MJPEG Video Decoder MFT' 'C:\Windows\System32\nvDecMFTMjpegx.dll'

    # Register as MFT in MediaFoundation\Transforms (HKCR)
    Write-Host "[4] Registering in MediaFoundation\Transforms..."
    if (-not (Test-Path 'HKCR:\')) { New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT | Out-Null }

    $mftBase = "HKCR:\MediaFoundation\Transforms"
    foreach ($entry in @(
        @{Clsid=$h264Clsid; Name='NVIDIA H.264 Encoder MFT'},
        @{Clsid=$hevcClsid; Name='NVIDIA HEVC Encoder MFT'},
        @{Clsid=$mjpegClsid; Name='NVIDIA MJPEG Video Decoder MFT'}
    )) {
        $p = "$mftBase\$($entry.Clsid.Trim('{').Trim('}'))"
        if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        Set-ItemProperty -Path $p -Name '(default)' -Value $entry.Name -Force
        Set-ItemProperty -Path $p -Name 'MFTFlags' -Value 4 -Type DWord -Force
        Write-Host "    MFT registered: $($entry.Name)"
    }

    # 5. Update DriverSupportModules to include MFT DLLs from System32
    Write-Host "[5] Adding MFT DLLs to DriverSupportModules..."
    $curMods = (Get-ItemProperty $classKey -Name 'DriverSupportModules' -EA SilentlyContinue).DriverSupportModules
    if ($curMods -notlike '*nvEncMFTH264x.dll*') {
        $newMods = $curMods + ' nvEncMFTH264x.dll nvEncMFThevcx.dll nvEncMFTav1x.dll nvDecMFTMjpegx.dll'
        Set-ItemProperty $classKey -Name 'DriverSupportModules' -Value $newMods
        Write-Host "    Updated."
    } else {
        Write-Host "    Already present."
    }

    Write-Host ""
    Write-Host "=== Verify MFT DLLs in System32 ==="
    @('nvEncMFTH264x.dll','nvEncMFThevcx.dll','nvDecMFTMjpegx.dll') | ForEach-Object {
        $p = "C:\Windows\System32\$_"
        if (Test-Path $p) { Write-Host "  OK: $p ($([math]::Round((Get-Item $p).Length/1KB,0)) KB)" }
        else { Write-Host "  MISSING: $p" }
    }

    Write-Host ""
    Write-Host "=== Verify CLSID registration ==="
    if (-not (Test-Path 'HKCR:\')) { New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT | Out-Null }
    @('{60F44560-5A20-4857-BFEF-D29773CB8040}','{966F107C-8EA2-425D-B822-E4A71BEF01D7}') | ForEach-Object {
        $p = "HKCR:\CLSID\$_\InprocServer32"
        if (Test-Path $p) {
            $val = (Get-ItemProperty $p).'(default)'
            Write-Host "  CLSID $_ -> $val"
        } else {
            Write-Host "  CLSID $_ NOT registered"
        }
    }

    Write-Host ""
    Write-Host "=== Find Parsec log ==="
    $logPaths = @(
        "$env:APPDATA\Parsec\parsec.log",
        'C:\ProgramData\Parsec\parsec.log',
        'C:\Users\bot\AppData\Roaming\Parsec\parsec.log',
        'C:\Program Files\Parsec\parsec.log'
    )
    foreach ($lp in $logPaths) {
        if (Test-Path $lp) { Write-Host "  LOG FOUND: $lp" }
    }
    Write-Host "  Searching all user profiles..."
    Get-ChildItem 'C:\Users' -Directory -EA SilentlyContinue | ForEach-Object {
        $p = "$($_.FullName)\AppData\Roaming\Parsec\parsec.log"
        if (Test-Path $p) { Write-Host "  LOG FOUND: $p" }
    }

    Write-Host ""
    Write-Host "=== HardwareInformation check ==="
    $p = Get-ItemProperty $classKey -EA SilentlyContinue
    $p | Get-Member -MemberType NoteProperty | Where-Object Name -like '*Hardware*' | ForEach-Object {
        Write-Host "  $($_.Name) = $($p.($_.Name))"
    }
    Write-Host "(should be empty - qwMemorySize removed)"
}
