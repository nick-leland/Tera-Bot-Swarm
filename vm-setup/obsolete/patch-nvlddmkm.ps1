$VMName  = 'TeraBot1'
$VMCred  = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
$workDir = 'C:\Windows\Temp\nvpatch'
$patchedFile = "$workDir\nvlddmkm_patched.sys"

Write-Host "=== Step 1: Apply binary patches ==="
$bytes = [System.IO.File]::ReadAllBytes("$workDir\nvlddmkm.sys")

# Helper: verify bytes at offset before patching
function Verify-And-Patch {
    param([byte[]]$buf, [int]$offset, [byte[]]$expect, [byte[]]$replace, [string]$name)
    $actual = $buf[$offset..($offset + $expect.Length - 1)]
    $hexActual  = ($actual  | ForEach-Object { $_.ToString('X2') }) -join ' '
    $hexExpect  = ($expect  | ForEach-Object { $_.ToString('X2') }) -join ' '
    $hexReplace = ($replace | ForEach-Object { $_.ToString('X2') }) -join ' '
    if (($actual | ForEach-Object { $_.ToString('X2') }) -join ' ' -eq $hexExpect) {
        for ($i = 0; $i -lt $replace.Length; $i++) { $buf[$offset + $i] = $replace[$i] }
        Write-Host "  PATCHED  0x$($offset.ToString('X8'))  $name"
        Write-Host "           $hexExpect -> $hexReplace"
        return $true
    } else {
        Write-Host "  MISMATCH 0x$($offset.ToString('X8'))  $name"
        Write-Host "           Expected: $hexExpect"
        Write-Host "           Actual:   $hexActual"
        return $false
    }
}

$patches = @(
    # Patch 1: Early init vendor check - CMP CX,10DE; JNZ far +1BC
    # JNZ rel32 (0F 85 xx xx xx xx) -> NOP x6
    @{ Offset=0x003093BE; Expect=[byte[]](0x0F,0x85,0xBC,0x01,0x00,0x00); Replace=[byte[]](0x90,0x90,0x90,0x90,0x90,0x90); Name="JNZ-far vendor!=10DE early-init" },

    # Patch 2: CMP dword[RSP+70h],10DE; JNZ +29
    @{ Offset=0x000F7984; Expect=[byte[]](0x75,0x29); Replace=[byte[]](0x90,0x90); Name="JNZ vendor!=10DE (stack cmp)" },

    # Patch 3: MOV ECX,10DE; CMP AX,CX; JNZ +29
    @{ Offset=0x0010885E; Expect=[byte[]](0x75,0x29); Replace=[byte[]](0x90,0x90); Name="JNZ vendor!=10DE (reg cmp)" },

    # Patch 4: MOV ECX,1414; CMP AX,CX; JE +15  (VEN_1414 special branch -> BSOD path)
    @{ Offset=0x005F5E24; Expect=[byte[]](0x74,0x15); Replace=[byte[]](0x90,0x90); Name="JE VEN_1414 special path" }
)

$allOk = $true
foreach ($p in $patches) {
    $ok = Verify-And-Patch $bytes $p.Offset $p.Expect $p.Replace $p.Name
    if (-not $ok) { $allOk = $false }
}

if (-not $allOk) {
    Write-Warning "Some patches had mismatches. Continuing anyway - mismatched patches were SKIPPED."
}

[System.IO.File]::WriteAllBytes($patchedFile, $bytes)
Write-Host ""
Write-Host "Patched file: $patchedFile ($([math]::Round((Get-Item $patchedFile).Length/1MB,1)) MB)"

Write-Host ""
Write-Host "=== Step 2: Sign patched driver with test cert ==="
# Create catalog for the patched file
$catTemp = "$workDir\nvlddmkm_patch.cat"
New-FileCatalog -Path $workDir -CatalogFilePath $catTemp -CatalogVersion 2 | Out-Null

# Find our test cert (should be in cert store from previous session)
$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object Subject -like '*NVTestDriver*' | Select-Object -First 1
if (-not $cert) {
    Write-Host "Test cert not found in LocalMachine\My - creating new one..."
    $cert = New-SelfSignedCertificate -Subject "CN=NVTestDriver" `
        -CertStoreLocation "Cert:\LocalMachine\My" `
        -KeyUsage DigitalSignature `
        -Type CodeSigning `
        -HashAlgorithm SHA256
    $certStore = [System.Security.Cryptography.X509Certificates.X509Store]::new('Root','LocalMachine')
    $certStore.Open('ReadWrite')
    $certStore.Add($cert)
    $certStore.Close()
    $tpStore = [System.Security.Cryptography.X509Certificates.X509Store]::new('TrustedPublisher','LocalMachine')
    $tpStore.Open('ReadWrite')
    $tpStore.Add($cert)
    $tpStore.Close()
    Write-Host "Created and trusted cert: $($cert.Thumbprint)"
}

$sig = Set-AuthenticodeSignature -FilePath $catTemp -Certificate $cert -TimestampServer $null
Write-Host "Catalog signed: $($sig.Status) (cert: $($cert.Subject))"

Write-Host ""
Write-Host "=== Step 3: Copy patched nvlddmkm.sys to VM ==="
# Stage to VM Temp first
Copy-VMFile -VMName $VMName -SourcePath $patchedFile `
    -DestinationPath 'C:\Windows\Temp\nvlddmkm_patched.sys' `
    -CreateFullPath -FileSource Host -Force
Write-Host "Staged patched sys to VM Temp"

# Also copy the INF and catalog we need
$infSrc = 'C:\Windows\Temp\nvidia-drv-new\nv_dispi_patched.inf'
if (Test-Path $infSrc) {
    Copy-VMFile -VMName $VMName -SourcePath $infSrc `
        -DestinationPath 'C:\Windows\Temp\nv_dispi_patched.inf' `
        -CreateFullPath -FileSource Host -Force
    Write-Host "Staged patched INF"
}

Write-Host ""
Write-Host "=== Step 4: Install in VM ==="
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Replace nvlddmkm.sys in existing staged DriverStore (from previous pnputil staging)
    $driverStore = 'C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_3210371373e48d7f'

    if (Test-Path $driverStore) {
        Write-Host "DriverStore exists, replacing nvlddmkm.sys..."
        $target = "$driverStore\nvlddmkm.sys"
        $backup = "$driverStore\nvlddmkm.sys.orig"

        # Backup original
        if (-not (Test-Path $backup)) {
            Copy-Item $target $backup -Force
            Write-Host "  Backed up original to .orig"
        }

        # Replace with patched version
        Copy-Item 'C:\Windows\Temp\nvlddmkm_patched.sys' $target -Force
        Write-Host "  Replaced nvlddmkm.sys with patched version"
        Write-Host "  Size: $([math]::Round((Get-Item $target).Length/1MB,1)) MB"
    } else {
        Write-Host "DriverStore NOT found: $driverStore"
        Write-Host "Need to run pnputil staging first"
        return
    }

    # Get our test cert in this VM session
    $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object Subject -like '*NVTestDriver*' | Select-Object -First 1
    if (-not $cert) {
        Write-Host "Creating test cert in VM..."
        $cert = New-SelfSignedCertificate -Subject "CN=NVTestDriver" `
            -CertStoreLocation "Cert:\LocalMachine\My" `
            -KeyUsage DigitalSignature -Type CodeSigning -HashAlgorithm SHA256
        foreach ($store in @('Root','TrustedPublisher')) {
            $s = [System.Security.Cryptography.X509Certificates.X509Store]::new($store,'LocalMachine')
            $s.Open('ReadWrite'); $s.Add($cert); $s.Close()
        }
        Write-Host "Cert created: $($cert.Thumbprint)"
    } else {
        Write-Host "Using existing test cert: $($cert.Thumbprint)"
    }

    # Sign the patched nvlddmkm.sys directly
    Write-Host ""
    Write-Host "Signing patched nvlddmkm.sys..."
    $sig = Set-AuthenticodeSignature -FilePath "$driverStore\nvlddmkm.sys" -Certificate $cert
    Write-Host "  Sign result: $($sig.Status)"

    # Also create a catalog for the whole DriverStore dir
    Write-Host ""
    Write-Host "Creating catalog..."
    $catPath = 'C:\Windows\Temp\nv_patch_new.cat'
    $drvCatFinal = "$driverStore\NV_DISP.CAT"
    New-FileCatalog -Path $driverStore -CatalogFilePath $catPath -CatalogVersion 2 | Out-Null
    $catSig = Set-AuthenticodeSignature -FilePath $catPath -Certificate $cert
    Write-Host "  Cat sign result: $($catSig.Status)"
    Copy-Item $catPath $drvCatFinal -Force
    Write-Host "  Catalog placed at $drvCatFinal"

    # Verify test signing is enabled
    Write-Host ""
    Write-Host "=== Test signing status ==="
    $bcd = bcdedit /enum all 2>&1
    if ($bcd -match 'testsigning.*Yes') { Write-Host "  Test signing: ENABLED" }
    elseif ($bcd -match 'testsigning') { Write-Host "  Test signing entry found (check value above)" }
    else {
        Write-Host "  Test signing: NOT ENABLED - enabling now..."
        bcdedit /set testsigning on
    }

    # Set Service to nvlddmkm for the VEN_1414 device
    Write-Host ""
    Write-Host "=== Setting nvlddmkm as Service for GPU-P device ==="
    $enumPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\VEN_1414&DEV_008E&SUBSYS_00000000&REV_00\5&59d1a3c&0&0'
    if (Test-Path $enumPath) {
        $current = (Get-ItemProperty $enumPath).Service
        Write-Host "  Current Service: $current"
        Set-ItemProperty -Path $enumPath -Name 'Service' -Value 'nvlddmkm' -Type String
        Write-Host "  Set Service = nvlddmkm"
    } else {
        # Try finding it
        $devices = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI' -EA SilentlyContinue |
            Where-Object PSPath -like '*VEN_1414*'
        foreach ($dev in $devices) {
            $subs = Get-ChildItem $dev.PSPath -EA SilentlyContinue
            foreach ($sub in $subs) {
                Write-Host "  Found device: $($sub.PSPath)"
                Set-ItemProperty -Path $sub.PSPath -Name 'Service' -Value 'nvlddmkm' -Type String
                Write-Host "  Set Service = nvlddmkm"
            }
        }
    }

    # Ensure nvlddmkm service is registered
    Write-Host ""
    Write-Host "=== Verify nvlddmkm service registration ==="
    $svcKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm'
    if (Test-Path $svcKey) {
        $svc = Get-ItemProperty $svcKey
        Write-Host "  Service exists: ImagePath=$($svc.ImagePath)"
    } else {
        Write-Host "  Service not found - creating minimal service entry..."
        New-Item -Path $svcKey -Force | Out-Null
        Set-ItemProperty $svcKey -Name 'Type' -Value 1 -Type DWord
        Set-ItemProperty $svcKey -Name 'Start' -Value 3 -Type DWord
        Set-ItemProperty $svcKey -Name 'ErrorControl' -Value 1 -Type DWord
        Set-ItemProperty $svcKey -Name 'ImagePath' -Value "\SystemRoot\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_3210371373e48d7f\nvlddmkm.sys" -Type ExpandString
        Set-ItemProperty $svcKey -Name 'Group' -Value 'Video' -Type String
        Write-Host "  Service entry created"
    }

    Write-Host ""
    Write-Host "=== Rebooting VM ==="
    Write-Host "If nvlddmkm.sys loads cleanly: Device Manager will show NVIDIA GeForce RTX 5090"
    Write-Host "If BSOD still occurs: we'll need deeper analysis"
    Write-Host ""
    Write-Host "Rebooting in 5 seconds..."
    Start-Sleep 5
    shutdown /r /t 0 /c "Testing patched nvlddmkm.sys"
}
