$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $store = 'C:\Windows\System32\HostDriverStore\FileRepository\nv_dispi.inf_amd64_6d8eaa80a18aada4'

    Write-Host '=== Catalog files in HostDriverStore ==='
    Get-ChildItem $store -Filter '*.cat' | Select-Object Name, Length

    Write-Host '=== Test: run D3D GPU load and check counter ==='
    # Quick GPU counter snapshot before
    $before = Get-Counter '\GPU Engine(*engtype_3d*)\Utilization Percentage' -ErrorAction SilentlyContinue
    $beforeVal = if ($before) { ($before.CounterSamples | Measure-Object CookedValue -Average).Average } else { 'N/A' }
    Write-Host "GPU 3D util before: $beforeVal %"

    Write-Host '=== Windows test signing status ==='
    $bcd = bcdedit /enum '{current}' 2>&1
    $bcd | Select-String 'testsigning|nointegrity' | ForEach-Object { Write-Host "  $($_.Line)" }

    Write-Host '=== Catalog verification for nvlddmkm.sys ==='
    $sys = Join-Path $store 'nvlddmkm.sys'
    if (Test-Path $sys) {
        $sig = Get-AuthenticodeSignature $sys
        Write-Host "  nvlddmkm.sys SignerCert: $($sig.SignerCertificate.Subject)"
        Write-Host "  Status: $($sig.Status)"
    }
    Write-Host '=== nv_dispi.inf signature ==='
    $inf = Join-Path $store 'nv_dispi.inf'
    if (Test-Path $inf) {
        $sig = Get-AuthenticodeSignature $inf
        Write-Host "  nv_dispi.inf Status: $($sig.Status)"
    }

    Write-Host '=== Check if test cert creation is feasible ==='
    $cert = Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -like '*Test*Driver*' } | Select-Object -First 1
    if ($cert) { Write-Host "Test cert exists: $($cert.Subject)" } else { Write-Host 'No test driver cert found' }
}
