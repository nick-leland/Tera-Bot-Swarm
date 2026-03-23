$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Find the VEN_1414 device registry path
    $devPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI'
    $ven1414Key = Get-ChildItem $devPath -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '*VEN_1414*DEV_008E*' } | Select-Object -First 1

    if ($ven1414Key) {
        Write-Host "Device key: $($ven1414Key.PSPath)"
        $instances = Get-ChildItem $ven1414Key.PSPath -ErrorAction SilentlyContinue
        foreach ($inst in $instances) {
            Write-Host "  Instance: $($inst.PSChildName)"
            $props = Get-ItemProperty $inst.PSPath -ErrorAction SilentlyContinue
            Write-Host "    Service: $($props.Service)"
            Write-Host "    Driver:  $($props.Driver)"
            Write-Host "    ConfigFlags: $($props.ConfigFlags)"

            # Check Control subkey
            $ctrlPath = Join-Path $inst.PSPath 'Control'
            if (Test-Path $ctrlPath) {
                $ctrl = Get-ItemProperty $ctrlPath -ErrorAction SilentlyContinue
                Write-Host "    Control\ActiveService: $($ctrl.ActiveService)"
            }
        }
    }

    Write-Host ""
    Write-Host "=== {4d36e968...}\0001 full registry for GPU-P device ==="
    $gpuKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001'
    $gpuProps = Get-ItemProperty $gpuKey -ErrorAction SilentlyContinue
    Write-Host "DriverDesc: $($gpuProps.DriverDesc)"
    Write-Host "ProviderName: $($gpuProps.ProviderName)"
    Write-Host "DriverVersion: $($gpuProps.DriverVersion)"
    Write-Host "ImagePath: $($gpuProps.ImagePath)"
    Write-Host "UserModeDriverName: $($gpuProps.UserModeDriverName)"
    Write-Host "InfPath: $($gpuProps.InfPath)"
    Write-Host "InfSection: $($gpuProps.InfSection)"

    Write-Host ""
    Write-Host "=== nvlddmkm service registry ==="
    $nvSvc = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm' -ErrorAction SilentlyContinue
    Write-Host "ImagePath: $($nvSvc.ImagePath)"
    Write-Host "Start: $($nvSvc.Start)"
    Write-Host "Type: $($nvSvc.Type)"

    Write-Host ""
    Write-Host "=== VirtualRender service registry ==="
    $vrSvc = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\VirtualRender' -ErrorAction SilentlyContinue
    Write-Host "ImagePath: $($vrSvc.ImagePath)"
    Write-Host "Start: $($vrSvc.Start)"
}
