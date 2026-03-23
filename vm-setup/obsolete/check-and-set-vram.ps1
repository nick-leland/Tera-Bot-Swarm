$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001'

    Write-Host "=== Current class key values (HardwareInformation) ==="
    $p = Get-ItemProperty $classKey -EA SilentlyContinue
    $p | Get-Member -MemberType NoteProperty | Where-Object Name -like '*Hardware*' | ForEach-Object {
        $val = $p.($_.Name)
        Write-Host "$($_.Name) = $val"
    }

    Write-Host ""
    Write-Host "=== All class key values ==="
    $p | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object {
        Write-Host "$($_.Name) = $($p.($_.Name))"
    }

    Write-Host ""
    Write-Host "=== Setting HardwareInformation.qwMemorySize = 16GB ==="
    # 16 GB in bytes as QWORD
    $16GB = [UInt64]16GB
    Write-Host "Setting to: $16GB bytes"
    Set-ItemProperty -Path $classKey -Name 'HardwareInformation.qwMemorySize' -Value $16GB -Type QWord -ErrorAction SilentlyContinue
    if ($?) {
        Write-Host "Set successfully"
    } else {
        Write-Host "Failed to set via Set-ItemProperty, trying reg.exe..."
        $hex = $16GB.ToString("X16")
        cmd /c "reg add `"HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001`" /v `"HardwareInformation.qwMemorySize`" /t REG_QWORD /d 0x$hex /f" 2>&1
    }

    Write-Host ""
    Write-Host "=== Also setting MemorySize (DWORD) ==="
    # Some apps read the 32-bit version
    Set-ItemProperty -Path $classKey -Name 'HardwareInformation.MemorySize' -Value ([UInt32](4096 * 1024 * 1024)) -Type DWord -ErrorAction SilentlyContinue
    if ($?) { Write-Host "MemorySize set to 4GB" }

    Write-Host ""
    Write-Host "=== Verify after set ==="
    $p2 = Get-ItemProperty $classKey -EA SilentlyContinue
    $p2 | Get-Member -MemberType NoteProperty | Where-Object Name -like '*Hardware*' | ForEach-Object {
        $val = $p2.($_.Name)
        Write-Host "$($_.Name) = $val"
    }

    Write-Host ""
    Write-Host "=== All DXGI adapters in VM (via GPU perf counters) ==="
    $counters = Get-Counter '\GPU Engine(*)\Utilization Percentage' -EA SilentlyContinue
    if ($counters) {
        $counters.CounterSamples | ForEach-Object {
            if ($_.InstanceName -match 'luid_0x([0-9a-f]+)_0x([0-9a-f]+)') {
                "$($Matches[1])_$($Matches[2])"
            }
        } | Sort-Object -Unique | ForEach-Object { Write-Host "  LUID: $_" }
    }

    Write-Host ""
    Write-Host "=== GpuPreference for TERA.exe ==="
    $gpuPref = Get-ItemProperty 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -EA SilentlyContinue
    Write-Host "TERA.exe   : $($gpuPref.'D:\TERA Starscape\Binaries\TERA.exe')"
    Write-Host "Launcher   : $($gpuPref.'D:\TERA Starscape\Tera Starscape Launcher.exe')"

    Write-Host ""
    Write-Host "Note: The HardwareInformation.qwMemorySize registry value is read by the"
    Write-Host "D3D/DXGI runtime when building adapter descriptions. Setting it to 16GB"
    Write-Host "may cause Windows to rank this adapter as 'high performance' for GpuPreference=2."
    Write-Host "TERA needs to be restarted to pick up the new adapter selection."
}
