$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host '=== Win32_VideoController ==='
    Get-WmiObject Win32_VideoController | Select-Object Name, AdapterCompatibility, DriverVersion, VideoProcessor | Format-List

    Write-Host '=== DXGI adapter info via registry ==='
    Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Video\*\0000' -ErrorAction SilentlyContinue |
        Select-Object Device_Description, DriverVersion, InstalledDisplayDrivers | Format-List

    Write-Host '=== WDDM version check ==='
    $wddmKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
    if (Test-Path $wddmKey) {
        Get-ItemProperty $wddmKey -ErrorAction SilentlyContinue | Format-List
    }

    Write-Host '=== dxdiag-style: D3D Feature Levels ==='
    Add-Type -AssemblyName System.DirectX -ErrorAction SilentlyContinue

    Write-Host '=== GPU adapter LUID registry entries ==='
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($props.DriverDesc) {
                Write-Host "  Adapter: $($props.DriverDesc)"
                Write-Host "    WddmVersion: $($props.WddmVersion)"
                Write-Host "    DriverVersion: $($props.DriverVersion)"
                Write-Host "    FeatureScore: $($props.FeatureScore)"
            }
        }
}
