$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
$hostStore = 'C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_4bf4c17fa8a478b5'

$mftDlls = @(
    'nvEncMFTH264x.dll',
    'nvEncMFThevcx.dll',
    'nvEncMFTav1x.dll',
    'nvDecMFTMjpegx.dll'
)

# Step 1: Copy to Temp (Copy-VMFile can write there)
Write-Host "=== Step 1: Staging DLLs to VM Temp ==="
foreach ($dll in $mftDlls) {
    $src = Join-Path $hostStore $dll
    $dst = "C:\Windows\Temp\$dll"
    if (Test-Path $src) {
        Write-Host "Staging $dll..."
        Copy-VMFile -VMName $VMName -SourcePath $src -DestinationPath $dst `
            -CreateFullPath -FileSource Host -Force -ErrorAction Stop
        Write-Host "  Staged OK"
    }
}

# Step 2: Move from Temp to System32 via PSRemoting (runs as admin)
Write-Host ""
Write-Host "=== Step 2: Moving from Temp to System32 ==="
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $dlls = @('nvEncMFTH264x.dll','nvEncMFThevcx.dll','nvEncMFTav1x.dll','nvDecMFTMjpegx.dll')
    foreach ($dll in $dlls) {
        $src = "C:\Windows\Temp\$dll"
        $dst = "C:\Windows\System32\$dll"
        if (Test-Path $src) {
            Copy-Item $src $dst -Force
            Write-Host "  Moved: $dll ($([math]::Round((Get-Item $dst).Length/1KB,0)) KB)"
        } else {
            Write-Host "  Not in Temp: $dll"
        }
    }

    Write-Host ""
    Write-Host "=== Step 3: Verify System32 ==="
    @('nvEncMFTH264x.dll','nvEncMFThevcx.dll','nvDecMFTMjpegx.dll') | ForEach-Object {
        $p = "C:\Windows\System32\$_"
        if (Test-Path $p) { Write-Host "  PRESENT: $_ ($([math]::Round((Get-Item $p).Length/1KB,0)) KB)" }
        else { Write-Host "  MISSING: $_" }
    }

    Write-Host ""
    Write-Host "=== Step 4: Find Parsec log ==="
    Get-ChildItem 'C:\Users' -Directory -EA SilentlyContinue | ForEach-Object {
        $p = "$($_.FullName)\AppData\Roaming\Parsec\parsec.log"
        if (Test-Path $p) {
            Write-Host "LOG: $p"
            Get-Content $p -Tail 30 | Select-String 'encode|ENCODE|NVENC|nvenc|H264|H.264|software|hardware|codec|MFT' |
                Select-Object -Last 20 | ForEach-Object { Write-Host "  $($_.Line)" }
        }
    }
    # Also check ProgramData
    $pd = 'C:\ProgramData\Parsec\parsec.log'
    if (Test-Path $pd) {
        Write-Host "LOG: $pd"
        Get-Content $pd -Tail 30 | Select-String 'encode|ENCODE|NVENC|software|hardware' |
            Select-Object -Last 20 | ForEach-Object { Write-Host "  $($_.Line)" }
    }

    Write-Host ""
    Write-Host "=== Step 5: Check current GPU/adapter state ==="
    Write-Host "GpuPreference removed? Check:"
    $gpuPref = Get-ItemProperty 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -EA SilentlyContinue
    if ($gpuPref) {
        $gpuPref | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -notlike 'PS*' } |
            ForEach-Object { Write-Host "  $($_.Name) = $($gpuPref.($_.Name))" }
    } else {
        Write-Host "  (key empty or missing)"
    }

    Write-Host ""
    Write-Host "HardwareInformation.qwMemorySize:"
    $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001'
    $p2 = Get-ItemProperty $classKey -Name 'HardwareInformation.qwMemorySize' -EA SilentlyContinue
    if ($p2) { Write-Host "  STILL SET: $($p2.'HardwareInformation.qwMemorySize')" }
    else { Write-Host "  REMOVED (good)" }
}
