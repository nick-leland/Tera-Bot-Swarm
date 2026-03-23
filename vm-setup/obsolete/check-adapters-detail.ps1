$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host '=== Windows version ==='
    [System.Environment]::OSVersion.Version
    (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ReleaseId
    (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion

    Write-Host '=== DXGI adapter enumeration with LUIDs ==='
    $code = @"
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct LUID { public uint LowPart; public int HighPart; }

[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
public struct DXGI_ADAPTER_DESC1 {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Description;
    public uint VendorId, DeviceId, SubSysId, Revision;
    public IntPtr DedicatedVideoMemory, DedicatedSystemMemory, SharedSystemMemory;
    public LUID AdapterLuid;
    public uint Flags;
}

[ComImport, Guid("29038f61-3839-4626-91fd-086879011a05"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IDXGIAdapter1 {
    void SetPrivateData(); void SetPrivateDataInterface(); void GetPrivateData(); void GetParent();
    void EnumOutputs(); void CheckInterfaceSupport();
    [PreserveSig] int GetDesc1(out DXGI_ADAPTER_DESC1 pDesc);
}

[ComImport, Guid("770aae78-f26f-4dba-a829-253c83d1b387"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IDXGIFactory1 {
    void SetPrivateData(); void SetPrivateDataInterface(); void GetPrivateData(); void GetParent();
    [PreserveSig] int EnumAdapters(uint Adapter, out IntPtr ppAdapter);
    void MakeWindowAssociation(); void GetWindowAssociation(); void CreateSwapChain(); void CreateSoftwareAdapter();
    [PreserveSig] int EnumAdapters1(uint Adapter, out IntPtr ppAdapter);
    void IsCurrent();
}

public class DxgiInfo {
    [DllImport("dxgi.dll")] static extern int CreateDXGIFactory1(ref Guid riid, out IntPtr pp);
    static Guid IID_Factory1 = new Guid("770aae78-f26f-4dba-a829-253c83d1b387");
    static Guid IID_Adapter1 = new Guid("29038f61-3839-4626-91fd-086879011a05");

    public static string[] Enum() {
        var results = new System.Collections.Generic.List<string>();
        try {
            IntPtr pp; var iid = IID_Factory1;
            if (CreateDXGIFactory1(ref iid, out pp) < 0) return new string[]{"Factory1 failed"};
            var factory = (IDXGIFactory1)Marshal.GetObjectForIUnknown(pp);
            Marshal.Release(pp);
            for (uint i=0;;i++) {
                IntPtr ap; int hr = factory.EnumAdapters1(i, out ap);
                if (hr == unchecked((int)0x887A0002)) break;
                var a = (IDXGIAdapter1)Marshal.GetObjectForIUnknown(ap);
                Marshal.Release(ap);
                DXGI_ADAPTER_DESC1 desc; a.GetDesc1(out desc);
                results.Add(string.Format("Adapter{0}: [{1}] VID={2:X4} DID={3:X4} LUID={4:X8}{5:X8} Flags={6} VidMem={7}MB",
                    i, desc.Description, desc.VendorId, desc.DeviceId,
                    desc.AdapterLuid.HighPart, desc.AdapterLuid.LowPart,
                    desc.Flags, (long)desc.DedicatedVideoMemory / 1024 / 1024));
            }
        } catch(Exception ex) { results.Add("Error: "+ex.Message); }
        return results.ToArray();
    }
}
"@
    try {
        Add-Type -TypeDefinition $code -ErrorAction Stop
        [DxgiInfo]::Enum() | ForEach-Object { Write-Host "  $_" }
    } catch {
        Write-Host "DXGI enum error: $($_.Exception.Message)"
    }

    Write-Host '=== GPU counter LUID ==='
    $c = Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction SilentlyContinue
    if ($c) {
        $c.CounterSamples | Select-Object -First 3 | ForEach-Object {
            if ($_.Path -match 'luid_0x(\w+)_0x(\w+)') { Write-Host "  LUID: high=0x$($Matches[1]) low=0x$($Matches[2])" }
        }
    }
}
