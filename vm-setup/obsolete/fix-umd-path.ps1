## Set UMD path to HostDriverStore (where nvldumdx.dll and nvwgf2umx.dll are co-located)
## matching how the host NVIDIA driver registers its UMD.

$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $store = 'C:\Windows\System32\HostDriverStore\FileRepository'

    # Find the folder with nvldumdx.dll
    $srcFolder = $null
    foreach ($f in @('nv_dispi.inf_amd64_4bf4c17fa8a478b5', 'nv_dispi.inf_amd64_6d8eaa80a18aada4')) {
        $candidate = Join-Path $store "$f\nvldumdx.dll"
        if (Test-Path $candidate) { $srcFolder = Join-Path $store $f; break }
    }

    if (!$srcFolder) { Write-Host 'ERROR: nvldumdx.dll not found in HostDriverStore'; exit }
    Write-Host "Using HostDriverStore folder: $srcFolder"

    # Verify nvwgf2umx.dll is also there (needed for nvldumdx.dll to load)
    $nvwgfPath = Join-Path $srcFolder 'nvwgf2umx.dll'
    Write-Host "nvwgf2umx.dll present: $(Test-Path $nvwgfPath)"
    if (!(Test-Path $nvwgfPath)) {
        # Copy it there from System32
        [System.IO.File]::Copy('C:\Windows\System32\nvwgf2umx.dll', $nvwgfPath, $true)
        Write-Host "Copied nvwgf2umx.dll to HostDriverStore"
    }

    $umdPath64 = Join-Path $srcFolder 'nvldumdx.dll'
    $umdPath32 = Join-Path $srcFolder 'nvldumd.dll'

    # Find GPU-P adapter key
    $regKey = $null
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($p.InfPath -like '*vrd*' -or $p.MatchingDeviceId -like '*VEN_1414*') {
                $regKey = $_.PSPath
            }
        }

    if (!$regKey) { Write-Host 'ERROR: GPU-P registry key not found'; exit }
    Write-Host "GPU-P registry key: $regKey"

    # Set UserModeDriverName to HostDriverStore path
    Set-ItemProperty -Path $regKey -Name 'UserModeDriverName' -Value ([string[]]@($umdPath64, $umdPath64, $umdPath64, $umdPath64)) -Type MultiString
    Write-Host "Set UserModeDriverName: $umdPath64"

    if (Test-Path $umdPath32) {
        Set-ItemProperty -Path $regKey -Name 'UserModeDriverNameWoW' -Value ([string[]]@($umdPath32, $umdPath32, $umdPath32, $umdPath32)) -Type MultiString
        Write-Host "Set UserModeDriverNameWoW: $umdPath32"
    }

    # Also set InstalledDisplayDrivers with full paths
    Set-ItemProperty -Path $regKey -Name 'InstalledDisplayDrivers' -Value ([string[]]@($umdPath64, $umdPath64, $umdPath64, $umdPath64, $umdPath32, $umdPath32, $umdPath32, $umdPath32)) -Type MultiString
    Write-Host "Set InstalledDisplayDrivers"

    # Restart NVIDIA device to apply
    Write-Host "Restarting NVIDIA device..."
    $nvidia = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' }
    if ($nvidia) {
        Disable-PnpDevice -InstanceId $nvidia.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 4
        Enable-PnpDevice -InstanceId $nvidia.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 6
        $nvidia2 = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' }
        Write-Host "NVIDIA status: $($nvidia2.Status)"
    }

    # Check dxdiag
    Write-Host "Running dxdiag..."
    $out = "$env:TEMP\dx4.txt"
    Start-Process dxdiag -ArgumentList "/t $out" -Wait -WindowStyle Hidden
    Start-Sleep -Seconds 6
    if (Test-Path $out) {
        Get-Content $out | Select-String 'Card name|Driver Model|WDDM|UserMode' | ForEach-Object { Write-Host "  $($_.Line.Trim())" }
        Remove-Item $out -Force
    }

    # Update the boot script to use HostDriverStore paths
    $umd64 = $umdPath64
    $umd32 = $umdPath32
    $bootScript = @"
`$log = 'C:\Windows\Temp\nvidia-dll-copy.log'
"[{0}] Starting NVIDIA UMD setup" -f (Get-Date) | Out-File `$log -Append

`$store = 'C:\Windows\System32\HostDriverStore\FileRepository'
`$src = `$null
foreach (`$f in @('nv_dispi.inf_amd64_4bf4c17fa8a478b5', 'nv_dispi.inf_amd64_6d8eaa80a18aada4')) {
    if (Test-Path (Join-Path `$store "`$f\nvldumdx.dll")) { `$src = Join-Path `$store `$f; break }
}

# Copy extra DLLs to System32 for app compatibility
if (`$src) {
    foreach (`$dll in @('nvwgf2umx.dll','nvapi64.dll','nvEncodeAPI64.dll','nvml.dll')) {
        `$sp = Join-Path `$src `$dll
        if (Test-Path `$sp) {
            try { [System.IO.File]::Copy(`$sp, "C:\Windows\System32\`$dll", `$true); "`  Copied: `$dll" | Out-File `$log -Append } catch { }
        }
    }
}

# Ensure UMD is registered with HostDriverStore path
`$regBase = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
Get-ChildItem `$regBase -ErrorAction SilentlyContinue | ForEach-Object {
    `$p = Get-ItemProperty `$_.PSPath -ErrorAction SilentlyContinue
    if (`$p.InfPath -like '*vrd*' -or `$p.MatchingDeviceId -like '*VEN_1414*') {
        `$umd64 = Join-Path `$src 'nvldumdx.dll'
        `$umd32 = Join-Path `$src 'nvldumd.dll'
        if (Test-Path `$umd64) {
            Set-ItemProperty `$_.PSPath -Name 'UserModeDriverName' -Value ([string[]]@(`$umd64,`$umd64,`$umd64,`$umd64)) -Type MultiString
            Set-ItemProperty `$_.PSPath -Name 'InstalledDisplayDrivers' -Value ([string[]]@(`$umd64,`$umd64,`$umd64,`$umd64)) -Type MultiString
            "  UMD set: `$umd64" | Out-File `$log -Append
        }
    }
}
"Done." | Out-File `$log -Append
"@
    [System.IO.File]::WriteAllText('C:\Windows\copy-nvidia-dlls.ps1', $bootScript, [System.Text.Encoding]::UTF8)
    Write-Host "Updated boot script to use HostDriverStore paths"
}
