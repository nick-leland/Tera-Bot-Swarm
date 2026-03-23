$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $out = "$env:TEMP\dxdiag_full.txt"
    Start-Process dxdiag -ArgumentList "/t $out" -Wait -WindowStyle Hidden
    Start-Sleep -Seconds 8

    if (Test-Path $out) {
        $content = Get-Content $out -Raw
        Write-Host "=== Full dxdiag output ($($content.Length) chars) ==="

        # Show section headers
        $content -split "`n" | Select-String '^\s*[-=]{3,}|^-{3,}|\[.*\]|Render Devices|Display Devices|DirectX' |
            Select-Object -First 50 | ForEach-Object { Write-Host $_.Line }

        Write-Host '=== Render Devices section ==='
        $inRender = $false
        foreach ($line in ($content -split "`n")) {
            if ($line -match 'Render Devices') { $inRender = $true }
            if ($inRender -and $line -match 'Sound Devices|Input Devices|Network Devices') { $inRender = $false }
            if ($inRender) { Write-Host $line }
        }

        Remove-Item $out -Force
    }

    # Also check via WMI if there's a separate GPU object
    Write-Host '=== Win32_DisplayControllerConfiguration ==='
    Get-WmiObject Win32_DisplayControllerConfiguration -ErrorAction SilentlyContinue | Format-List *

    # Check GPU adapter in DxgKrnl
    Write-Host '=== DxgKrnl GPU adapters (registry) ==='
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($p.DriverDesc) {
                $umd = if ($p.UserModeDriverName) { $p.UserModeDriverName[0] } else { '(none)' }
                Write-Host "  $($p.DriverDesc)"
                Write-Host "    UMD: $umd"
                Write-Host "    WddmVersion: $($p.WddmVersion)"
                Write-Host "    FeatureScore: $($p.FeatureScore)"
            }
        }
}
