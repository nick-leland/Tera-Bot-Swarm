## Register NVIDIA user-mode driver for the GPU-P (VEN_1414) adapter in VM.
## This sets UserModeDriverName in registry so DXGI/Task Manager sees the GPU.

$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $store = 'C:\Windows\System32\HostDriverStore\FileRepository'
    $sys32 = 'C:\Windows\System32'

    Write-Host '=== Searching for nvldumdx.dll in HostDriverStore ==='
    $found = Get-ChildItem $store -Recurse -Filter 'nvldumdx.dll' -ErrorAction SilentlyContinue
    $found | Select-Object FullName, Length

    # Also check 4bf4c17 folder for key DLLs
    $folders = Get-ChildItem $store -Directory | Where-Object { $_.Name -like 'nv_dispi*' }
    foreach ($f in $folders) {
        Write-Host "--- $($f.Name) ---"
        Get-ChildItem $f.FullName -Filter 'nvl*.dll' -ErrorAction SilentlyContinue | Select-Object Name, Length
    }

    Write-Host '=== Find GPU-P adapter registry key ==='
    $gpuPKey = $null
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($props.MatchingDeviceId -like '*VEN_1414*' -or $props.InfPath -like '*vrd*') {
                Write-Host "Found GPU-P key: $($_.PSPath)"
                Write-Host "  DriverDesc: $($props.DriverDesc)"
                Write-Host "  UserModeDriverName: $($props.UserModeDriverName)"
                $gpuPKey = $_.PSPath
            }
        }
}
