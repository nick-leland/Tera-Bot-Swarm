$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host '=== NVIDIA PnP ==='
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA*' } | Select-Object Status, FriendlyName

    Write-Host '=== Run dxdiag ==='
    $out = "$env:TEMP\dxdiag2.txt"
    Start-Process dxdiag -ArgumentList "/t $out" -Wait -WindowStyle Hidden
    Start-Sleep -Seconds 6
    if (Test-Path $out) {
        $content = Get-Content $out
        # Extract display device sections
        $capture = $false
        foreach ($line in $content) {
            if ($line -match 'Display Devices') { $capture = $true }
            if ($capture -and ($line -match 'Sound Devices|Input Devices|Music Devices')) { $capture = $false }
            if ($capture -and $line -match 'Card name|WDDM|DDI|Feature Level|Driver Model|Driver Version|UserMode') {
                Write-Host $line
            }
        }
        Remove-Item $out -Force
    }

    Write-Host '=== GPU adapter registry keys ==='
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($p.DriverDesc) {
                Write-Host "  $($p.DriverDesc) | UMD: $($p.UserModeDriverName | Select-Object -First 1)"
            }
        }

    Write-Host '=== GPU engine counter categories (phys_ check) ==='
    $c = Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction SilentlyContinue
    if ($c) {
        $c.CounterSamples | ForEach-Object { $_.Path } |
            ForEach-Object { if ($_ -match 'phys_(\d+).*engtype_(\w+)') { "$($Matches[1]): $($Matches[2])" } } |
            Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
    }
}
