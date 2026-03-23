## Run from HOST. Installs the NVIDIA GPU-P user-mode driver inside the VM via pnputil.
## This registers nvwgf2umx.dll as the UMD for PCI\VEN_1414&DEV_008E so DXGI sees it.

$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $store = 'C:\Windows\System32\HostDriverStore\FileRepository'

    # Find nv_dispi.inf folders (prefer newer 4bf4c17, then 6d8eaa80)
    $folders = @(
        (Join-Path $store 'nv_dispi.inf_amd64_4bf4c17fa8a478b5'),
        (Join-Path $store 'nv_dispi.inf_amd64_6d8eaa80a18aada4')
    )

    $infPath = $null
    foreach ($f in $folders) {
        $candidate = Join-Path $f 'nv_dispi.inf'
        if (Test-Path $candidate) { $infPath = $candidate; break }
    }

    if (!$infPath) {
        Write-Host 'ERROR: nv_dispi.inf not found in HostDriverStore'
        exit 1
    }
    Write-Host "Using INF: $infPath"

    # Check if INF contains the GPU-P device ID (VEN_1414&DEV_008E)
    $infContent = Get-Content $infPath -TotalCount 300
    $hasGpuP = $infContent | Select-String 'VEN_1414' -Quiet
    Write-Host "INF contains VEN_1414 (GPU-P device): $hasGpuP"

    if (!$hasGpuP) {
        Write-Host 'INF does not have GPU-P device ID. Checking current device driver...'
        # Show what's bound to the device
        pnputil /enum-devices /deviceid "PCI\VEN_1414&DEV_008E" /drivers
        exit 1
    }

    Write-Host 'Running pnputil to install/update driver...'
    $result = pnputil /add-driver $infPath /install 2>&1
    Write-Host $result

    Write-Host '=== Device driver after pnputil ==='
    pnputil /enum-devices /deviceid "PCI\VEN_1414&DEV_008E" /drivers

    Write-Host '=== Registry UserModeDriverName after install ==='
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($props.DriverDesc -like '*Virtual Render*' -or $props.DriverDesc -like '*NVIDIA*') {
                Write-Host "--- $($props.DriverDesc) ---"
                Write-Host "  UserModeDriverName: $($props.UserModeDriverName)"
                Write-Host "  WddmVersion: $($props.WddmVersion)"
            }
        }
}
