## Update the copy-nvidia-dlls.ps1 boot script in VM to include nvldumdx.dll
## and also re-register the UMD on each boot (in case it gets cleared).

$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $copyScript = @'
$log = 'C:\Windows\Temp\nvidia-dll-copy.log'
"[{0}] Starting NVIDIA DLL+UMD setup" -f (Get-Date) | Out-File $log -Append

# Find best HostDriverStore folder
$store = 'C:\Windows\System32\HostDriverStore\FileRepository'
$folders = @(
    (Join-Path $store 'nv_dispi.inf_amd64_4bf4c17fa8a478b5'),
    (Join-Path $store 'nv_dispi.inf_amd64_6d8eaa80a18aada4')
)
$src = $null
foreach ($f in $folders) {
    if (Test-Path (Join-Path $f 'nvwgf2umx.dll')) { $src = $f; break }
    if (Test-Path (Join-Path $f 'nvldumdx.dll')) { $src = $f; break }
}

if (!$src) {
    "No HostDriverStore folder found" | Out-File $log -Append
    exit
}
"Using source: $src" | Out-File $log -Append

# Copy DLLs to System32
$dlls = @('nvwgf2umx.dll', 'nvapi64.dll', 'nvEncodeAPI64.dll', 'nvml.dll', 'nvldumdx.dll', 'nvldumd.dll')
foreach ($dll in $dlls) {
    $srcPath = Join-Path $src $dll
    $dstPath = "C:\Windows\System32\$dll"
    if (!(Test-Path $srcPath)) { continue }
    try {
        [System.IO.File]::Copy($srcPath, $dstPath, $true)
        "  Copied: $dll" | Out-File $log -Append
    } catch {
        "  Error copying $dll : $($_.Exception.Message)" | Out-File $log -Append
    }
}

# Ensure UserModeDriverName is registered for GPU-P adapter (VEN_1414)
$regBase = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
Get-ChildItem $regBase -ErrorAction SilentlyContinue | ForEach-Object {
    $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
    if ($p.InfPath -like '*vrd*' -or $p.MatchingDeviceId -like '*VEN_1414*') {
        $umd = $p.UserModeDriverName
        if (!$umd -or $umd.Count -eq 0 -or $umd[0] -notlike '*nvl*') {
            $path = 'C:\Windows\System32\nvldumdx.dll'
            Set-ItemProperty $_.PSPath -Name 'UserModeDriverName' -Value ([string[]]@($path,$path,$path,$path)) -Type MultiString
            Set-ItemProperty $_.PSPath -Name 'InstalledDisplayDrivers' -Value ([string[]]@('nvldumdx.dll','nvldumdx.dll','nvldumdx.dll','nvldumdx.dll')) -Type MultiString
            "  Registered UMD: $path" | Out-File $log -Append
        } else {
            "  UMD already set: $($umd[0])" | Out-File $log -Append
        }
    }
}

"Done." | Out-File $log -Append
'@
    [System.IO.File]::WriteAllText('C:\Windows\copy-nvidia-dlls.ps1', $copyScript, [System.Text.Encoding]::UTF8)
    Write-Host 'Updated C:\Windows\copy-nvidia-dlls.ps1 with nvldumdx.dll + UMD registration'

    Write-Host '=== Verifying current System32 DLLs ==='
    foreach ($f in @('nvldumdx.dll', 'nvldumd.dll', 'nvwgf2umx.dll', 'nvapi64.dll')) {
        $p = "C:\Windows\System32\$f"
        if (Test-Path $p) {
            $sz = [math]::Round((Get-Item $p).Length / 1MB, 2)
            Write-Host "  OK: $f ($sz MB)"
        } else { Write-Host "  MISSING: $f" }
    }
}
