$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

$hostInf = 'C:\Users\chaot\Programming\tera_project\vm-setup\nvgpup.inf'
$workDir = 'C:\Windows\Temp\nvgpup'

Write-Host "=== Step 1: Sign INF with test cert on host ==="
$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object Subject -like '*NVTestDriver*' | Select-Object -First 1
if (-not $cert) {
    $cert = New-SelfSignedCertificate -Subject "CN=NVTestDriver" `
        -CertStoreLocation "Cert:\LocalMachine\My" `
        -KeyUsage DigitalSignature -Type CodeSigning -HashAlgorithm SHA256
    foreach ($store in @('Root','TrustedPublisher')) {
        $s = [System.Security.Cryptography.X509Certificates.X509Store]::new($store,'LocalMachine')
        $s.Open('ReadWrite'); $s.Add($cert); $s.Close()
    }
    Write-Host "Created cert: $($cert.Thumbprint)"
} else {
    Write-Host "Using existing cert: $($cert.Thumbprint)"
}

# Create temp dir for INF + catalog
New-Item -Path $workDir -ItemType Directory -Force | Out-Null
Copy-Item $hostInf "$workDir\nvgpup.inf" -Force

# Create catalog
$catPath = "$workDir\nvgpup.cat"
New-FileCatalog -Path $workDir -CatalogFilePath $catPath -CatalogVersion 2 | Out-Null
$catSig = Set-AuthenticodeSignature -FilePath $catPath -Certificate $cert
Write-Host "Catalog signed: $($catSig.Status)"

Write-Host ""
Write-Host "=== Step 2: Stage INF to VM ==="
Copy-VMFile -VMName $VMName -SourcePath "$workDir\nvgpup.inf" `
    -DestinationPath 'C:\Windows\Temp\nvgpup\nvgpup.inf' `
    -CreateFullPath -FileSource Host -Force
Copy-VMFile -VMName $VMName -SourcePath $catPath `
    -DestinationPath 'C:\Windows\Temp\nvgpup\nvgpup.cat' `
    -CreateFullPath -FileSource Host -Force
Write-Host "Copied INF and catalog to VM"

Write-Host ""
Write-Host "=== Step 3: Install in VM ==="
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $infDir = 'C:\Windows\Temp\nvgpup'
    $inf    = "$infDir\nvgpup.inf"

    Write-Host "--- Install test cert in VM ---"
    $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object Subject -like '*NVTestDriver*' | Select-Object -First 1
    if (-not $cert) {
        $cert = New-SelfSignedCertificate -Subject "CN=NVTestDriver" `
            -CertStoreLocation "Cert:\LocalMachine\My" `
            -KeyUsage DigitalSignature -Type CodeSigning -HashAlgorithm SHA256
        foreach ($store in @('Root','TrustedPublisher')) {
            $s = [System.Security.Cryptography.X509Certificates.X509Store]::new($store,'LocalMachine')
            $s.Open('ReadWrite'); $s.Add($cert); $s.Close()
        }
    }

    # Re-sign catalog with VM cert (catalog must be signed by a cert trusted IN THE VM)
    $catSig = Set-AuthenticodeSignature -FilePath "$infDir\nvgpup.cat" -Certificate $cert
    Write-Host "  Cat signed in VM: $($catSig.Status)"

    Write-Host ""
    Write-Host "--- Verify nvlddmkm.sys in System32\drivers ---"
    $sys = 'C:\Windows\System32\drivers\nvlddmkm.sys'
    if (Test-Path $sys) {
        Write-Host "  PRESENT: $([math]::Round((Get-Item $sys).Length/1MB,1)) MB"
        $sig = Get-AuthenticodeSignature $sys
        Write-Host "  Signature: $($sig.Status)"
    } else {
        Write-Host "  MISSING - will be needed!"
    }

    Write-Host ""
    Write-Host "--- Test signing status ---"
    $bcd = bcdedit /enum {current} 2>&1
    if ($bcd -match 'testsigning\s+Yes') { Write-Host "  Test signing: ENABLED" }
    else {
        Write-Host "  Enabling test signing..."
        bcdedit /set testsigning on
    }

    Write-Host ""
    Write-Host "--- pnputil /add-driver ---"
    $addResult = pnputil /add-driver $inf /install 2>&1
    $addResult | ForEach-Object { Write-Host "  $_" }

    Write-Host ""
    Write-Host "--- Check what drivers matched ---"
    pnputil /enum-drivers /class Display 2>&1 | Select-String 'nvgpup|VEN_1414|Published Name|Driver Date' |
        Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }

    Write-Host ""
    Write-Host "--- GPU device current state ---"
    $instId = 'PCI\VEN_1414&DEV_008E&SUBSYS_00000000&REV_00\5&59D1A3C&0&0'
    $dev = Get-PnpDevice -InstanceId $instId -EA SilentlyContinue
    Write-Host "  Status: $($dev.Status)  Code: $($dev.ProblemCode)"

    $svc = (Get-PnpDeviceProperty -InstanceId $instId -KeyName 'DEVPKEY_Device_Service' -EA SilentlyContinue).Data
    $inf2 = (Get-PnpDeviceProperty -InstanceId $instId -KeyName 'DEVPKEY_Device_DriverInfPath' -EA SilentlyContinue).Data
    Write-Host "  Service: $svc"
    Write-Host "  InfPath: $inf2"
}
