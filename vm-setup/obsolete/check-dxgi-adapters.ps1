$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Enumerate DXGI adapters via inline C#
    $code = @"
using System;
using System.Runtime.InteropServices;

public class DxgiEnum {
    [DllImport("dxgi.dll")]
    static extern int CreateDXGIFactory1(ref Guid riid, out IntPtr ppFactory);

    static Guid IID_IDXGIFactory1 = new Guid("770aae78-f26f-4dba-a829-253c83d1b387");

    [ComImport, Guid("770aae78-f26f-4dba-a829-253c83d1b387"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDXGIFactory1 {
        [PreserveSig] int SetPrivateData(ref Guid Name, uint DataSize, IntPtr pData);
        [PreserveSig] int SetPrivateDataInterface(ref Guid Name, IntPtr pUnknown);
        [PreserveSig] int GetPrivateData(ref Guid Name, ref uint pDataSize, IntPtr pData);
        [PreserveSig] int GetParent(ref Guid riid, out IntPtr ppParent);
        [PreserveSig] int EnumAdapters(uint Adapter, out IntPtr ppAdapter);
        [PreserveSig] int MakeWindowAssociation(IntPtr WindowHandle, uint Flags);
        [PreserveSig] int GetWindowAssociation(out IntPtr pWindowHandle);
        [PreserveSig] int CreateSwapChain(IntPtr pDevice, IntPtr pDesc, out IntPtr ppSwapChain);
        [PreserveSig] int CreateSoftwareAdapter(IntPtr Module, out IntPtr ppAdapter);
        [PreserveSig] int EnumAdapters1(uint Adapter, out IntPtr ppAdapter);
        [PreserveSig] int IsCurrent(out int pCurrent);
    }

    public static string[] ListAdapters() {
        var results = new System.Collections.Generic.List<string>();
        try {
            IntPtr factory;
            var iid = IID_IDXGIFactory1;
            int hr = CreateDXGIFactory1(ref iid, out factory);
            if (hr < 0) { return new string[] { "CreateDXGIFactory1 failed: 0x" + hr.ToString("X") }; }
            var fact = (IDXGIFactory1)Marshal.GetObjectForIUnknown(factory);
            for (uint i = 0; ; i++) {
                IntPtr adapter;
                hr = fact.EnumAdapters1(i, out adapter);
                if (hr == unchecked((int)0x887A0002)) break; // DXGI_ERROR_NOT_FOUND
                results.Add("Adapter " + i + ": " + adapter.ToString("X"));
                Marshal.Release(adapter);
            }
            Marshal.Release(factory);
        } catch (Exception ex) {
            results.Add("Error: " + ex.Message);
        }
        return results.ToArray();
    }
}
"@

    try {
        Add-Type -TypeDefinition $code -ErrorAction Stop
        $adapters = [DxgiEnum]::ListAdapters()
        Write-Host '=== DXGI Adapters ==='
        $adapters | ForEach-Object { Write-Host "  $_" }
    } catch {
        Write-Host "DXGI enumeration error: $($_.Exception.Message)"
    }

    Write-Host '=== GPU-P adapter registry details ==='
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($props.DriverDesc -like '*Virtual Render*' -or $props.DriverDesc -like '*NVIDIA*') {
                Write-Host "--- $($props.DriverDesc) ---"
                $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | Format-Table Name, Value -AutoSize
            }
        }

    Write-Host '=== Check vrd.inf installed driver details ==='
    pnputil /enum-drivers 2>$null | Select-String -Pattern 'vrd|nvidia|virtual render' -Context 3 -CaseSensitive:$false
}
