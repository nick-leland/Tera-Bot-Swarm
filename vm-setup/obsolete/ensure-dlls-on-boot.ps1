## Run this ONCE from the host to add a startup task inside the VM
## that re-copies NVIDIA DLLs from HostDriverStore to System32 on each boot.
## This ensures the DLLs survive if Windows ever clears them.

$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Verify current DLLs are still present
    Write-Host '=== Current NVIDIA DLL state ==='
    foreach ($f in @('nvwgf2umx.dll', 'nvapi64.dll', 'nvEncodeAPI64.dll', 'nvcuda.dll', 'nvml.dll')) {
        $p = "C:\Windows\System32\$f"
        if (Test-Path $p) {
            $sz = [math]::Round((Get-Item $p).Length / 1MB, 1)
            Write-Host "  EXISTS: $f ($sz MB)"
        } else {
            Write-Host "  MISSING: $f"
        }
    }

    # Write a copy-on-boot script that runs at startup (SYSTEM)
    $copyScript = @'
$log = 'C:\Windows\Temp\nvidia-dll-copy.log'
"[{0}] Starting NVIDIA DLL copy" -f (Get-Date) | Out-File $log -Append

# Find best HostDriverStore folder (prefer newer 4bf4c17, fallback to 6d8eaa80)
$store = 'C:\Windows\System32\HostDriverStore\FileRepository'
$folders = @(
    (Join-Path $store 'nv_dispi.inf_amd64_4bf4c17fa8a478b5'),
    (Join-Path $store 'nv_dispi.inf_amd64_6d8eaa80a18aada4')
)
$src = $null
foreach ($f in $folders) {
    if (Test-Path (Join-Path $f 'nvwgf2umx.dll')) { $src = $f; break }
}

if (!$src) {
    "No HostDriverStore folder found with nvwgf2umx.dll" | Out-File $log -Append
    exit
}
"Using source: $src" | Out-File $log -Append

$dlls = @('nvwgf2umx.dll', 'nvapi64.dll', 'nvEncodeAPI64.dll', 'nvml.dll')
foreach ($dll in $dlls) {
    $srcPath = Join-Path $src $dll
    $dstPath = "C:\Windows\System32\$dll"
    if (!(Test-Path $srcPath)) { continue }
    try {
        [System.IO.File]::Copy($srcPath, $dstPath, $true)
        "  Copied: $dll" | Out-File $log -Append
    } catch {
        "  Error copying $dll : $($_.Exception.Message)" | Out-File $log -Append
    }
}
"Done." | Out-File $log -Append
'@
    [System.IO.File]::WriteAllText('C:\Windows\copy-nvidia-dlls.ps1', $copyScript, [System.Text.Encoding]::UTF8)
    Write-Host 'Wrote C:\Windows\copy-nvidia-dlls.ps1'

    # Register as SYSTEM AtStartup task
    $existing = Get-ScheduledTask -TaskName 'Copy-NVIDIA-DLLs' -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName 'Copy-NVIDIA-DLLs' -Confirm:$false
    }

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Windows\copy-nvidia-dlls.ps1'
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
    Register-ScheduledTask -TaskName 'Copy-NVIDIA-DLLs' -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings | Out-Null
    Write-Host 'Registered Copy-NVIDIA-DLLs scheduled task (AtStartup, SYSTEM)'

    Write-Host '=== All scheduled tasks ==='
    Get-ScheduledTask | Where-Object { $_.TaskName -in @('Fix-NVIDIA-GPU', 'Copy-NVIDIA-DLLs', 'StartParsecAtLogon') } |
        Select-Object TaskName, State | Format-Table -AutoSize
}
