$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host "=== Verifying CLSID registration location ==="
    # Check HKLM (system-wide, accessible to all users including Parsec service)
    $h264 = '{60F44560-5A20-4857-BFEF-D29773CB8040}'
    $hevc = '{966F107C-8EA2-425D-B822-E4A71BEF01D7}'

    foreach ($clsid in @($h264, $hevc)) {
        $hklm = "HKLM:\SOFTWARE\Classes\CLSID\$clsid\InprocServer32"
        $hkcu = "HKCU:\SOFTWARE\Classes\CLSID\$clsid\InprocServer32"
        if (Test-Path $hklm) { Write-Host "HKLM (system-wide): $clsid -> $((Get-ItemProperty $hklm).'(default)')" }
        elseif (Test-Path $hkcu) { Write-Host "HKCU (user-only):   $clsid -> $((Get-ItemProperty $hkcu).'(default)')" }
        else { Write-Host "NOT REGISTERED: $clsid" }
    }

    Write-Host ""
    Write-Host "=== Ensuring HKLM system-wide CLSID registration ==="
    # Re-register in HKLM explicitly so all processes can see it
    function Register-MFT-HKLM {
        param($Clsid, $FriendlyName, $DllPath)
        $base = "HKLM:\SOFTWARE\Classes\CLSID\$Clsid"
        $ip = "$base\InprocServer32"
        New-Item -Path $base -Force | Out-Null
        Set-ItemProperty -Path $base -Name '(default)' -Value $FriendlyName
        New-Item -Path $ip -Force | Out-Null
        Set-ItemProperty -Path $ip -Name '(default)' -Value $DllPath
        Set-ItemProperty -Path $ip -Name 'ThreadingModel' -Value 'Both'

        # Also register in MFT transforms
        $mftPath = "HKLM:\SOFTWARE\Classes\MediaFoundation\Transforms\$($Clsid.Trim('{').Trim('}'))"
        New-Item -Path $mftPath -Force | Out-Null
        Set-ItemProperty -Path $mftPath -Name '(default)' -Value $FriendlyName
        Set-ItemProperty -Path $mftPath -Name 'MFTFlags' -Value 4 -Type DWord
        Write-Host "  HKLM registered: $FriendlyName"
    }

    Register-MFT-HKLM '{60F44560-5A20-4857-BFEF-D29773CB8040}' 'NVIDIA H.264 Encoder MFT' 'C:\Windows\System32\nvEncMFTH264x.dll'
    Register-MFT-HKLM '{966F107C-8EA2-425D-B822-E4A71BEF01D7}' 'NVIDIA HEVC Encoder MFT' 'C:\Windows\System32\nvEncMFThevcx.dll'
    Register-MFT-HKLM '{70F36578-2741-454F-B494-E8563DDD1CB4}' 'NVIDIA MJPEG Video Decoder MFT' 'C:\Windows\System32\nvDecMFTMjpegx.dll'

    Write-Host ""
    Write-Host "=== Check where Parsec is running from ==="
    $parsec = Get-Process -Name 'parsecd','parsec' -ErrorAction SilentlyContinue
    if ($parsec) {
        $parsec | ForEach-Object { Write-Host "  PID $($_.Id): $($_.ProcessName) - $($_.Path)" }
        # Find the log near the executable
        $parsec | ForEach-Object {
            $dir = Split-Path $_.Path -Parent
            $log = Join-Path $dir 'parsec.log'
            if (Test-Path $log) { Write-Host "  LOG: $log" }
        }
    } else {
        Write-Host "  Parsec not running"
    }

    # Search for any parsec.log anywhere
    Write-Host ""
    Write-Host "=== Searching for parsec.log ==="
    @('C:\ProgramData\Parsec', 'C:\Program Files\Parsec') | ForEach-Object {
        if (Test-Path $_) {
            Get-ChildItem $_ -Recurse -Filter '*.log' -EA SilentlyContinue | ForEach-Object {
                Write-Host "  Found: $($_.FullName)"
            }
        }
    }
    Get-ChildItem 'C:\Users' -Directory -EA SilentlyContinue | ForEach-Object {
        $base = "$($_.FullName)\AppData"
        if (Test-Path $base) {
            Get-ChildItem $base -Recurse -Filter 'parsec.log' -EA SilentlyContinue | ForEach-Object {
                Write-Host "  Found: $($_.FullName)"
            }
        }
    }
}

Write-Host ""
Write-Host "=== Rebooting VM ==="
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { shutdown /r /t 3 /c "Rebooting to apply MFT encoder registration" }
Write-Host "Reboot initiated. Wait 30-60 seconds then reconnect via Parsec."
