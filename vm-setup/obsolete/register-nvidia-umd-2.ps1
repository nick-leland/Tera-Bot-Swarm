## Full UMD registration for GPU-P adapter.
## Copies nvldumdx.dll to System32 and registers it in adapter registry key.

$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $store = 'C:\Windows\System32\HostDriverStore\FileRepository'
    $sys32 = 'C:\Windows\System32'

    # Check what's in the 4bf4c17 folder
    $f4 = Join-Path $store 'nv_dispi.inf_amd64_4bf4c17fa8a478b5'
    if (Test-Path $f4) {
        Write-Host '=== 4bf4c17 folder contents (nvl* files) ==='
        Get-ChildItem $f4 -Filter 'nvl*.dll' -ErrorAction SilentlyContinue | Select-Object Name, Length
        Write-Host '=== 4bf4c17 total files ==='
        (Get-ChildItem $f4 -ErrorAction SilentlyContinue).Count
    }

    # Find best source for nvldumdx.dll
    $srcFolder = $null
    foreach ($f in @('nv_dispi.inf_amd64_4bf4c17fa8a478b5', 'nv_dispi.inf_amd64_6d8eaa80a18aada4')) {
        $candidate = Join-Path $store "$f\nvldumdx.dll"
        if (Test-Path $candidate) { $srcFolder = Join-Path $store $f; break }
    }

    if (!$srcFolder) { Write-Host 'ERROR: nvldumdx.dll not found'; exit 1 }
    Write-Host "Source folder: $srcFolder"

    # Copy nvldumdx.dll and nvldumd.dll to System32
    foreach ($dll in @('nvldumdx.dll', 'nvldumd.dll')) {
        $src = Join-Path $srcFolder $dll
        $dst = Join-Path $sys32 $dll
        if (Test-Path $src) {
            try {
                [System.IO.File]::Copy($src, $dst, $true)
                $sz = [math]::Round((Get-Item $dst).Length / 1MB, 2)
                Write-Host "  COPIED: $dll ($sz MB)"
            } catch {
                Write-Host "  ERROR: $dll -> $($_.Exception.Message)"
            }
        } else {
            Write-Host "  NOT IN SOURCE: $dll"
        }
    }

    # Set registry values for GPU-P adapter
    $regKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001'

    $umdPath = 'C:\Windows\System32\nvldumdx.dll'
    $umdPathWow = 'C:\Windows\System32\nvldumd.dll'

    # UserModeDriverName - REG_MULTI_SZ, 4 entries (standard WDDM pattern)
    Set-ItemProperty -Path $regKey -Name 'UserModeDriverName' -Value ([string[]]@($umdPath, $umdPath, $umdPath, $umdPath)) -Type MultiString
    Write-Host "Set UserModeDriverName: $umdPath"

    Set-ItemProperty -Path $regKey -Name 'UserModeDriverNameWoW' -Value ([string[]]@($umdPathWow, $umdPathWow, $umdPathWow, $umdPathWow)) -Type MultiString
    Write-Host "Set UserModeDriverNameWoW: $umdPathWow"

    # InstalledDisplayDrivers - just filenames
    $installed = [string[]]@('nvldumdx.dll','nvldumdx.dll','nvldumdx.dll','nvldumdx.dll','nvldumd.dll','nvldumd.dll','nvldumd.dll','nvldumd.dll')
    Set-ItemProperty -Path $regKey -Name 'InstalledDisplayDrivers' -Value $installed -Type MultiString
    Write-Host "Set InstalledDisplayDrivers"

    # Verify
    $props = Get-ItemProperty $regKey
    Write-Host "=== Registry after update ==="
    Write-Host "  UserModeDriverName: $($props.UserModeDriverName)"
    Write-Host "  UserModeDriverNameWoW: $($props.UserModeDriverNameWoW)"
    Write-Host "  InstalledDisplayDrivers: $($props.InstalledDisplayDrivers | Select-Object -First 2)"

    # Trigger device re-enumeration (disable/enable)
    Write-Host "=== Restarting GPU-P device ==="
    $nvidia = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' -and $_.Status -eq 'OK' }
    if ($nvidia) {
        Disable-PnpDevice -InstanceId $nvidia.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        Enable-PnpDevice -InstanceId $nvidia.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        $nvidia2 = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' }
        Write-Host "NVIDIA status after restart: $($nvidia2.Status)"
    }

    Write-Host "=== Final adapter registry check ==="
    $propsAfter = Get-ItemProperty $regKey
    Write-Host "  UserModeDriverName count: $($propsAfter.UserModeDriverName.Count)"
    Write-Host "  First UMD: $($propsAfter.UserModeDriverName[0])"
}
