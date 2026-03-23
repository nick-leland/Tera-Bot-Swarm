$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Run dxdiag and capture output
    $out = "$env:TEMP\dxdiag_out.txt"
    Start-Process dxdiag -ArgumentList "/t $out" -Wait -WindowStyle Hidden
    Start-Sleep -Seconds 5
    if (Test-Path $out) {
        $content = Get-Content $out
        # Show display adapter sections
        $inDisplay = $false
        foreach ($line in $content) {
            if ($line -match 'Display Devices') { $inDisplay = $true }
            if ($inDisplay -and $line -match '^\s*$') { $inDisplay = $false }
            if ($inDisplay -or $line -match 'Card name|Driver Version|WDDM|Feature Level|DDI') {
                Write-Host $line
            }
        }
        Remove-Item $out -Force
    } else {
        Write-Host 'dxdiag output not found'
    }

    Write-Host '=== WDDM version via registry deep check ==='
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($props.DriverDesc) {
                Write-Host "--- $($props.DriverDesc) ---"
                $props | Select-Object WddmVersion, UserModeDriverName, FeatureScore, DriverVersion | Format-List
            }
        }
}
