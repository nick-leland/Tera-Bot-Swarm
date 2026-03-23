$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Write-Host "Rebooting VM..."
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { Restart-Computer -Force } -ErrorAction SilentlyContinue

Start-Sleep -Seconds 20
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 10
    try {
        $r = Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { 'ok' } -ErrorAction Stop
        if ($r -eq 'ok') { Write-Host "VM online ($($i*10+20)s)"; break }
    } catch { Write-Host "  Waiting... ($($i*10+20)s)" }
}

Start-Sleep -Seconds 5

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host "=== GPU-P UMD check ==="
    $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001'
    $p = Get-ItemProperty $classKey
    Write-Host "DriverDesc: $($p.DriverDesc)"
    Write-Host "UMD: $(($p.UserModeDriverName)[0])"
    Write-Host "InfPath: $($p.InfPath)"

    Write-Host ""
    Write-Host "=== GPU 3D utilization (baseline) ==="
    $s1 = (Get-Counter '\GPU Engine(*engtype_3d*)\Utilization Percentage' -ErrorAction SilentlyContinue)
    $v1 = if ($s1) { ($s1.CounterSamples | Measure-Object CookedValue -Average).Average } else { 'N/A' }
    Write-Host "3D util (idle): $v1 %"

    Write-Host ""
    Write-Host "=== Running D3D11 load test ==="
    # Run a quick DirectX test using a built-in tool
    $dxdiag = Start-Process dxdiag -ArgumentList '/64bit /t C:\Windows\Temp\dxtest.txt' -Wait -PassThru -ErrorAction SilentlyContinue
    if (Test-Path 'C:\Windows\Temp\dxtest.txt') {
        Get-Content 'C:\Windows\Temp\dxtest.txt' | Select-String 'Card|Feature Level|WDDM|Vendor|Display Memory' | ForEach-Object { $_.Line.Trim() }
    }

    Write-Host ""
    Write-Host "=== GPU 3D utilization after dxdiag ==="
    $s2 = (Get-Counter '\GPU Engine(*engtype_3d*)\Utilization Percentage' -ErrorAction SilentlyContinue)
    $v2 = if ($s2) { ($s2.CounterSamples | Measure-Object CookedValue -Average).Average } else { 'N/A' }
    Write-Host "3D util (post-dxdiag): $v2 %"

    Write-Host ""
    Write-Host "=== VEN_1414 status ==="
    Get-PnpDevice | Where-Object { $_.InstanceId -like '*VEN_1414*' } | Select-Object Status, FriendlyName, Problem
}
