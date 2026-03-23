$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $tmpDir = 'C:\Windows\Temp\nvidia-drv-new'
    $infPath = Join-Path $tmpDir 'nv_dispi.inf'
    $catFinal = Join-Path $tmpDir 'NV_DISP.CAT'
    $catTemp = 'C:\Windows\Temp\nv_test_driver.cat'

    # Step 1: Get or create self-signed test code signing certificate
    Write-Host "=== Test certificate ==="
    $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq 'CN=NVTestDriver' } | Select-Object -First 1
    if (-not $cert) {
        $cert = New-SelfSignedCertificate `
            -Type CodeSigningCert `
            -Subject 'CN=NVTestDriver' `
            -KeySpec Signature `
            -KeyUsage DigitalSignature `
            -FriendlyName 'NVIDIA Test Driver Cert' `
            -NotAfter (Get-Date).AddYears(10) `
            -CertStoreLocation 'Cert:\LocalMachine\My'
        Write-Host "Created cert: $($cert.Thumbprint)"
    } else {
        Write-Host "Reusing cert: $($cert.Thumbprint)"
    }

    # Add cert to Trusted Root and TrustedPublisher
    Write-Host "=== Adding to trust stores ==="
    foreach ($storeName in @('Root', 'TrustedPublisher')) {
        $store = [System.Security.Cryptography.X509Certificates.X509Store]::new($storeName, 'LocalMachine')
        $store.Open('ReadWrite')
        $store.Add($cert)
        $store.Close()
        Write-Host "  Added to $storeName"
    }

    # Step 2: Remove old catalog if exists (as file or dir)
    if (Test-Path $catFinal) { Remove-Item $catFinal -Recurse -Force }
    if (Test-Path $catTemp) { Remove-Item $catTemp -Force }

    # Step 3: Create new catalog at temp path (outside driver dir)
    Write-Host "=== Creating catalog at $catTemp ==="
    $newCat = New-FileCatalog -Path $tmpDir -CatalogFilePath $catTemp -CatalogVersion 2
    Write-Host "Catalog created: $($newCat.FullName), size: $([math]::Round($newCat.Length/1KB,1)) KB"

    # Step 4: Sign the catalog file
    Write-Host "=== Signing catalog ==="
    $sig = Set-AuthenticodeSignature -FilePath $catTemp -Certificate $cert
    Write-Host "Signature status: $($sig.Status)"

    # Step 5: Copy signed catalog into driver dir as NV_DISP.CAT
    Copy-Item $catTemp $catFinal -Force
    Write-Host "Copied signed catalog to $catFinal"

    # Step 6: Run pnputil
    Write-Host "=== pnputil /add-driver /install ==="
    $result = pnputil /add-driver $infPath /install 2>&1
    Write-Host $result

    # Check result
    if ($result -like '*Driver package added successfully*' -or $result -like '*0 error*') {
        Write-Host "SUCCESS"
    } else {
        Write-Host "FAILED - checking error code..."
        $result2 = pnputil /add-driver $infPath 2>&1
        Write-Host "Staging only: $result2"
    }

    Write-Host "=== NVIDIA device status ==="
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA*' -or $_.InstanceId -like '*VEN_1414*' } |
        Select-Object Status, FriendlyName, InstanceId | Format-List

    Write-Host "=== GPU adapter registry ==="
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($p.DriverDesc) {
                $umd = if ($p.UserModeDriverName) { $p.UserModeDriverName[0] } else { '(none)' }
                Write-Host "  $($p.DriverDesc) | UMD: $umd | Ver: $($p.DriverVersion)"
            }
        }
}
