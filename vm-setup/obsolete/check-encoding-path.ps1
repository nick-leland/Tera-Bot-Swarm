$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host "=== Parsec log - encoding lines (last 100) ==="
    $logPath = "$env:APPDATA\Parsec\parsec.log"
    if (Test-Path $logPath) {
        Get-Content $logPath -Tail 200 |
            Select-String 'encoder|encode|nvenc|NVENC|software|hardware|H264|hevc|HEVC|codec|bitrate|GPU|adapter|DXGI|surface|capture|fps|frame' -CaseSensitive:$false |
            Select-Object -Last 60 | ForEach-Object { Write-Host $_.Line }
    } else {
        Write-Host "No parsec.log at $logPath"
    }

    Write-Host ""
    Write-Host "=== nvEncMFTH264x.dll - is it present? ==="
    $mftPaths = @(
        'C:\Windows\System32\nvEncMFTH264x.dll',
        'C:\Windows\System32\nvEncMFThevcx.dll',
        'C:\Windows\System32\nvEncodeAPI64.dll',
        'C:\Windows\System32\nvapi64.dll'
    )
    foreach ($p in $mftPaths) {
        if (Test-Path $p) {
            $f = Get-Item $p
            Write-Host "PRESENT: $p ($([math]::Round($f.Length/1KB,0)) KB)"
        } else {
            Write-Host "MISSING: $p"
        }
    }

    Write-Host ""
    Write-Host "=== MFT encoder registration ==="
    $mftKey = 'HKLM:\SOFTWARE\Microsoft\Windows Media Foundation\Transforms'
    if (Test-Path $mftKey) {
        Get-ChildItem $mftKey -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object { Get-ItemProperty $_.PSPath -EA SilentlyContinue } |
            Where-Object { $_ -and ($_.FriendlyName -like '*NVENC*' -or $_.FriendlyName -like '*NVIDIA*' -or $_.FriendlyName -like '*H264*' -or $_.FriendlyName -like '*H.264*') } |
            ForEach-Object { Write-Host "MFT: $($_.FriendlyName) @ $($_.PSPath.Split('\')[-1])" }
    }

    Write-Host ""
    Write-Host "=== Check MFT by CLSID for known NVIDIA encoders ==="
    # Known NVIDIA H264 MFT CLSID
    $nvH264Clsid = '{9A432DB4-1847-4B16-9C99-1B602AF3C1F1}'
    $clsidPath = "HKLM:\SOFTWARE\Classes\CLSID\$nvH264Clsid"
    if (Test-Path $clsidPath) {
        Write-Host "NVIDIA H264 MFT CLSID registered: $nvH264Clsid"
        $p = Get-ItemProperty $clsidPath -EA SilentlyContinue
        $ip = Get-ItemProperty "$clsidPath\InprocServer32" -EA SilentlyContinue
        Write-Host "  FriendlyName: $($p.'(default)')"
        Write-Host "  Server: $($ip.'(default)')"
    } else {
        Write-Host "NVIDIA H264 MFT NOT registered (CLSID $nvH264Clsid)"
    }

    Write-Host ""
    Write-Host "=== Check Parsec encoding config ==="
    $cfg = "$env:APPDATA\Parsec\config.json"
    if (Test-Path $cfg) {
        $j = Get-Content $cfg -Raw | ConvertFrom-Json -EA SilentlyContinue
        if ($j) {
            Write-Host "encoder_h265 : $($j.encoder_h265)"
            Write-Host "encoder_bitrate: $($j.encoder_bitrate)"
            Write-Host "encode_mode : $($j.encode_mode)"
        } else {
            Get-Content $cfg
        }
    }

    Write-Host ""
    Write-Host "=== TERA GPU usage (if running) ==="
    $vmGpu = Get-Counter '\GPU Engine(*)\Utilization Percentage' -EA SilentlyContinue
    if ($vmGpu) {
        $vmGpu.CounterSamples | Where-Object CookedValue -gt 0.01 |
            Select-Object InstanceName, @{N='Pct';E={[math]::Round($_.CookedValue,3)}} |
            Sort-Object Pct -Descending | Format-Table -AutoSize
    }

    Write-Host ""
    Write-Host "=== HardwareInformation values ==="
    $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001'
    $p2 = Get-ItemProperty $classKey -EA SilentlyContinue
    $p2 | Get-Member -MemberType NoteProperty | Where-Object Name -like '*Hardware*' | ForEach-Object {
        Write-Host "$($_.Name) = $($p2.($_.Name))"
    }
}
