$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $teraBase = 'D:\TERA Starscape'
    $configDirs = @(
        "$teraBase\Engine\Config",
        "$teraBase\S1Game\Config"
    )

    Write-Host "=== TERA Config - GPU/Rendering relevant settings ==="
    foreach ($dir in $configDirs) {
        if (-not (Test-Path $dir)) { continue }
        $inis = Get-ChildItem $dir -Filter '*.ini' -ErrorAction SilentlyContinue
        foreach ($ini in $inis) {
            $lines = Get-Content $ini.FullName -ErrorAction SilentlyContinue |
                Select-String -Pattern 'D3D|GPU|Adapter|Render|Display|Resolution|Window|VSync|MaxFPS|FullScreen|UseVsync|bSmoothFrame|AllowD3D|TextureGroup|DetailMode|SystemSettings|RenderDevice|GraphicsAdapter' -CaseSensitive:$false
            if ($lines) {
                Write-Host ""
                Write-Host "--- $($ini.FullName) ---"
                $lines | ForEach-Object { Write-Host $_.Line }
            }
        }
    }

    Write-Host ""
    Write-Host "=== DXGI adapter enumeration (C#) ==="
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DXGIEnum {
    [DllImport("dxgi.dll")] static extern int CreateDXGIFactory1(ref Guid riid, out IntPtr ppFactory);
    [DllImport("dxgi.dll")] static extern int CreateDXGIFactory2(uint flags, ref Guid riid, out IntPtr ppFactory);

    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct DXGI_ADAPTER_DESC1 {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Description;
        public uint VendorId, DeviceId, SubSysId, Revision;
        public UIntPtr DedicatedVideoMemory, DedicatedSystemMemory, SharedSystemMemory;
        public long AdapterLuid;
        public uint Flags;
    }

    public static void EnumAdapters() {
        Guid factoryGuid = new Guid("770aae78-f26f-4dba-a829-253c83d1b387");
        IntPtr factory;
        int hr = CreateDXGIFactory1(ref factoryGuid, out factory);
        if (hr < 0) { Console.WriteLine("CreateDXGIFactory1 failed: " + hr.ToString("X8")); return; }

        IntPtr pGetAdapter = Marshal.ReadIntPtr(Marshal.ReadIntPtr(factory), 6 * IntPtr.Size);
        // Use vtable to enum adapters
        // Instead, use simpler approach via COM
        Marshal.Release(factory);
        Console.WriteLine("Factory created OK, using WMI for adapter list instead");
    }
}
"@ -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "=== WMI GPU adapters ==="
    Get-WmiObject Win32_VideoController | Select-Object Name, AdapterRAM, DeviceID, DriverVersion, VideoProcessor | Format-List

    Write-Host ""
    Write-Host "=== DXGI adapters via PowerShell COM ==="
    $dxgi = [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()

    # Enumerate via registry (DXGI adapter LUIDs stored here)
    $gpuPref = Get-ItemProperty 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -ErrorAction SilentlyContinue
    Write-Host "Current UserGpuPreferences:"
    $gpuPref | Format-List

    Write-Host ""
    Write-Host "=== GPU-P adapter LUID ==="
    # Get LUID from D3DKMT
    $kmt = @"
using System;
using System.Runtime.InteropServices;
public class D3DKMT {
    [StructLayout(LayoutKind.Sequential)]
    public struct D3DKMT_OPENADAPTERFROMGDIDISPLAYNAME {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DeviceName;
        public uint hAdapter;
        public long AdapterLuid;
        public uint VidPnSourceId;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct D3DKMT_ENUMADAPTERS2 {
        public uint NumAdapters;
        public IntPtr pAdapters;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct D3DKMT_ADAPTERINFO {
        public uint hAdapter;
        public long AdapterLuid;
        public ulong NumOfSources;
        public bool bPresentMoveRegionsPreferred;
    }
    [DllImport("gdi32.dll")] public static extern int D3DKMTEnumAdapters2(ref D3DKMT_ENUMADAPTERS2 pData);
    [DllImport("gdi32.dll")] public static extern int D3DKMTOpenAdapterFromGdiDisplayName(ref D3DKMT_OPENADAPTERFROMGDIDISPLAYNAME pData);

    public static void EnumAll() {
        var e = new D3DKMT_ENUMADAPTERS2();
        e.NumAdapters = 0;
        e.pAdapters = IntPtr.Zero;
        int hr = D3DKMTEnumAdapters2(ref e);
        Console.WriteLine("NumAdapters: " + e.NumAdapters + " (hr=" + hr.ToString("X8") + ")");

        if (e.NumAdapters > 0 && hr == 0) {
            int sz = Marshal.SizeOf(typeof(D3DKMT_ADAPTERINFO));
            e.pAdapters = Marshal.AllocHGlobal((int)(sz * e.NumAdapters));
            hr = D3DKMTEnumAdapters2(ref e);
            Console.WriteLine("Enum result: " + hr.ToString("X8"));
            for (int i = 0; i < e.NumAdapters; i++) {
                var info = (D3DKMT_ADAPTERINFO)Marshal.PtrToStructure(
                    IntPtr.Add(e.pAdapters, i * sz), typeof(D3DKMT_ADAPTERINFO));
                Console.WriteLine("  Adapter[" + i + "]: hAdapter=" + info.hAdapter.ToString("X")
                    + " LUID=0x" + info.AdapterLuid.ToString("X16")
                    + " Sources=" + info.NumOfSources);
            }
            Marshal.FreeHGlobal(e.pAdapters);
        }
    }
}
"@
    Add-Type -TypeDefinition $kmt -ErrorAction SilentlyContinue
    try { [D3DKMT]::EnumAll() } catch { Write-Host "D3DKMT enum failed: $_" }

    Write-Host ""
    Write-Host "=== VEN_1414 PnP device (GPU-P) ==="
    $dev = Get-PnpDevice | Where-Object { $_.InstanceId -like '*VEN_1414*' } | Select-Object -First 1
    if ($dev) {
        $props = Get-PnpDeviceProperty -InputObject $dev -ErrorAction SilentlyContinue
        $luid = $props | Where-Object KeyName -eq 'DEVPKEY_Device_Luid'
        Write-Host "FriendlyName: $($dev.FriendlyName)"
        Write-Host "Status: $($dev.Status)"
        Write-Host "LUID: $($luid.Data)"
        Write-Host "InstanceId: $($dev.InstanceId)"
    }

    Write-Host ""
    Write-Host "=== TERA.exe command line support check ==="
    Write-Host "TERA binary:"
    Get-Item "$teraBase\Binaries\TERA.exe" -ErrorAction SilentlyContinue | Select-Object FullName, Length, LastWriteTime
    Write-Host ""
    Write-Host "Launcher:"
    Get-ChildItem "$teraBase" -Filter '*Launcher*' -ErrorAction SilentlyContinue | Select-Object FullName, Length
}
