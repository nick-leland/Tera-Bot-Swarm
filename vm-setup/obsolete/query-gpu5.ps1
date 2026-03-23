. "$PSScriptRoot\config.ps1"

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {

    Write-Host "=== BCD state ===" -ForegroundColor Cyan
    bcdedit /enum | Select-String "testsign|nointegrit|bootmenupol"

    Write-Host ""
    Write-Host "=== CI TestMode (kernel-level testsigning) ===" -ForegroundColor Cyan
    # This key is set by the kernel at boot when testsigning is active
    $ciPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CI"
    if (Test-Path $ciPath) {
        Get-ItemProperty $ciPath -ErrorAction SilentlyContinue |
            Select-Object -Property * -ExcludeProperty PS* | Format-List
    } else {
        Write-Host "  CI key not found" -ForegroundColor Red
    }
    # Also check the Protected sub-key
    $ciConfig = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config"
    if (Test-Path $ciConfig) {
        Write-Host "  CI\Config:" -ForegroundColor Green
        Get-ItemProperty $ciConfig -ErrorAction SilentlyContinue | Format-List
    } else {
        Write-Host "  CI\Config not found" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "=== Test Mode watermark indicator ===" -ForegroundColor Cyan
    # CSRSS sets this during boot when testsigning is on
    $testMode = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CI" -Name "TestMode" -ErrorAction SilentlyContinue)
    if ($testMode) { Write-Host "  TestMode value: $($testMode.TestMode)" -ForegroundColor Green }
    else { Write-Host "  TestMode value: NOT SET (testsigning may not be active at kernel)" -ForegroundColor Red }

    Write-Host ""
    Write-Host "=== TrustedPublisher store ===" -ForegroundColor Cyan
    $tp = Get-ChildItem "Cert:\LocalMachine\TrustedPublisher" -ErrorAction SilentlyContinue
    if ($tp) {
        $tp | Format-Table Thumbprint, Subject, NotAfter -AutoSize
    } else {
        Write-Host "  EMPTY - no certs in TrustedPublisher" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "=== Root store (test certs) ===" -ForegroundColor Cyan
    Get-ChildItem "Cert:\LocalMachine\Root" | Where-Object { $_.Subject -like "*VrdGpuP*" -or $_.Subject -like "*NvGpuP*" } |
        Format-Table Thumbprint, Subject, NotAfter -AutoSize

    Write-Host ""
    Write-Host "=== oem4.inf (our test-signed package) ===" -ForegroundColor Cyan
    $oem4 = "C:\Windows\INF\oem4.inf"
    if (Test-Path $oem4) {
        Get-Content $oem4 | Select-Object -First 15
        Write-Host ""
        Write-Host "  Catalog: C:\Windows\INF\oem4.cat"
        $cat = "C:\Windows\INF\oem4.cat"
        if (Test-Path $cat) {
            # Check who signed the catalog
            $sig = Get-AuthenticodeSignature $cat -ErrorAction SilentlyContinue
            Write-Host "  Catalog status: $($sig.Status)"
            Write-Host "  Signer cert:    $($sig.SignerCertificate.Subject)"
            Write-Host "  Signer thumb:   $($sig.SignerCertificate.Thumbprint)"
        }
    } else {
        Write-Host "  oem4.inf NOT FOUND" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "=== vrd.sys in DriverStore (our test-signed copy) ===" -ForegroundColor Cyan
    $vrdFolders = Get-ChildItem "C:\Windows\System32\DriverStore\FileRepository" -Filter "vrd.inf_*" -Directory
    foreach ($f in $vrdFolders) {
        $sys = "$($f.FullName)\vrd.sys"
        if (Test-Path $sys) {
            $ver = (Get-Item $sys).VersionInfo.FileVersion
            Write-Host "  $($f.Name): vrd.sys $ver"
        }
    }

    Write-Host ""
    Write-Host "=== GPU-P device state ===" -ForegroundColor Cyan
    Get-PnpDevice | Where-Object { $_.InstanceId -like "*VEN_1414*" } |
        Format-Table FriendlyName, Status, InstanceId -AutoSize

    $dev = Get-WmiObject Win32_PnPEntity | Where-Object { $_.DeviceID -like "*VEN_1414*DEV_008E*" } | Select-Object -First 1
    if ($dev) {
        Write-Host "  ConfigManagerErrorCode: $($dev.ConfigManagerErrorCode)"
        $props = Get-WmiObject Win32_PnPSignedDriver | Where-Object { $_.DeviceID -like "*VEN_1414*DEV_008E*" } | Select-Object -First 1
        if ($props) { Write-Host "  DriverVersion: $($props.DriverVersion)" }
    }

    Write-Host ""
    Write-Host "=== VirtualRender service ===" -ForegroundColor Cyan
    $svc = Get-Service VirtualRender -ErrorAction SilentlyContinue
    if ($svc) { Write-Host "  Status: $($svc.Status)  StartType: $($svc.StartType)" }
    else { Write-Host "  VirtualRender service not found" -ForegroundColor Red }

    Write-Host ""
    Write-Host "=== Windows version ===" -ForegroundColor Cyan
    [System.Environment]::OSVersion.Version
    (Get-ComputerInfo).WindowsBuildLabEx
}
