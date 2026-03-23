$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host "=== Parsec log (last 50 lines) ==="
    $logPath = "$env:APPDATA\Parsec\parsec.log"
    if (Test-Path $logPath) {
        Get-Content $logPath -Tail 80 | Select-String 'encoder|encode|nvenc|NVENC|nvldd|vrd|GPU|adapter|DXGI|dx|d3d|display' -CaseSensitive:$false |
            Select-Object -Last 40 | ForEach-Object { Write-Host $_.Line }
    } else {
        Write-Host "No parsec.log at $logPath"
        Get-ChildItem "$env:APPDATA\Parsec" -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "=== Parsec config ==="
    $cfg = "$env:APPDATA\Parsec\config.json"
    if (Test-Path $cfg) { Get-Content $cfg } else { Write-Host "No config.json" }

    Write-Host ""
    Write-Host "=== D3D adapter check ==="
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)]
public struct DXGI_ADAPTER_DESC {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)]
    public string Description;
    public int VendorId, DeviceId, SubSysId, Revision;
    public IntPtr DedicatedVideoMemory, DedicatedSystemMemory, SharedSystemMemory;
    public long AdapterLuid;
}
"@ -ErrorAction SilentlyContinue

    Write-Host "=== nvEncodeAPI availability ==="
    $nvEnc = Get-Item 'C:\Windows\System32\nvEncodeAPI64.dll' -ErrorAction SilentlyContinue
    if ($nvEnc) { Write-Host "nvEncodeAPI64.dll present: $([math]::Round($nvEnc.Length/1MB,2)) MB" }
    else { Write-Host "nvEncodeAPI64.dll: NOT in System32" }

    # Check in DriverStore
    $nvEncDS = Get-ChildItem 'C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_3210371373e48d7f\nvEncodeAPI64.dll' -ErrorAction SilentlyContinue
    if ($nvEncDS) { Write-Host "nvEncodeAPI64.dll in new DriverStore: OK" }

    Write-Host ""
    Write-Host "=== GPU-P device current state ==="
    $dev = Get-PnpDevice | Where-Object { $_.InstanceId -like '*VEN_1414*' }
    $dev | Select-Object Status, FriendlyName, Problem | Format-List

    $gpuKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001'
    $p = Get-ItemProperty $gpuKey
    Write-Host "DriverDesc: $($p.DriverDesc)"
    Write-Host "DriverVersion: $($p.DriverVersion)"
    Write-Host "UMD: $(if ($p.UserModeDriverName) { $p.UserModeDriverName[0] } else { '(none)' })"
    Write-Host "InfPath: $($p.InfPath)"

    Write-Host ""
    Write-Host "=== WDDM version ==="
    \$wddm = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ItemProperty \$_.PSPath -ErrorAction SilentlyContinue } |
        Where-Object { \$_.DriverDesc } |
        Select-Object DriverDesc, WddmVersion
    \$wddm | Format-Table -AutoSize
}
