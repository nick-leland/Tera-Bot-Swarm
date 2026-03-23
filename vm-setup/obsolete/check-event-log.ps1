$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host '=== System events: DxgKrnl / Display / DXGI (last 20) ==='
    Get-WinEvent -LogName System -MaxEvents 500 -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -match 'dxg|display|nvidia|vrd|render' -or $_.Message -match 'WDDM|UserMode|UMD|adapter' } |
        Select-Object -Last 20 |
        ForEach-Object { Write-Host "[$($_.TimeCreated)] $($_.ProviderName): $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))" }

    Write-Host '=== Application events: DXGI failures ==='
    Get-WinEvent -LogName Application -MaxEvents 200 -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match 'DXGI|D3D11|display adapter|UMD|nvldumdx|nvwgf' } |
        Select-Object -Last 10 |
        ForEach-Object { Write-Host "[$($_.TimeCreated)] $($_.ProviderName): $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length)))" }

    Write-Host '=== Win32_VideoController (current) ==='
    Get-WmiObject Win32_VideoController |
        Select-Object Name, AdapterCompatibility, DriverVersion, VideoProcessor, CurrentHorizontalResolution | Format-List

    Write-Host '=== Check DXGI via simple D3D11 CreateDevice test ==='
    $code = @"
using System;
using System.Runtime.InteropServices;
public class D3DTest {
    [DllImport("d3d11.dll")]
    static extern int D3D11CreateDevice(
        IntPtr pAdapter, int DriverType, IntPtr Software, uint Flags,
        IntPtr pFeatureLevels, uint FeatureLevels, uint SDKVersion,
        out IntPtr ppDevice, out int pFeatureLevel, out IntPtr ppImmediateContext);
    public static string Test() {
        IntPtr dev, ctx; int fl;
        int hr = D3D11CreateDevice(IntPtr.Zero, 1, IntPtr.Zero, 0, IntPtr.Zero, 0, 7, out dev, out fl, out ctx);
        return "D3D11CreateDevice(HARDWARE): 0x" + hr.ToString("X8") + " FeatureLevel: 0x" + fl.ToString("X");
    }
}
"@
    try {
        Add-Type -TypeDefinition $code -ErrorAction Stop
        Write-Host ([D3DTest]::Test())
    } catch {
        Write-Host "D3D11 test error: $($_.Exception.Message)"
    }
}
