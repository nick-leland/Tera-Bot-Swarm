$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $src = 'C:\Windows\System32\HostDriverStore\FileRepository\nv_dispi.inf_amd64_6d8eaa80a18aada4'
    $dst = 'C:\Windows\System32'

    foreach ($dll in @('nvapi64.dll', 'nvEncodeAPI64.dll', 'nvml.dll')) {
        $srcPath = Join-Path $src $dll
        $dstPath = Join-Path $dst $dll
        try {
            [System.IO.File]::Copy($srcPath, $dstPath, $true)
            $sz = [math]::Round((Get-Item $dstPath).Length / 1MB, 1)
            Write-Host "  COPIED: $dll ($sz MB)"
        } catch {
            $err = $_.Exception.Message
            Write-Host "  ERROR: $dll -> $err"
        }
    }

    Write-Host '=== Final DLL check ==='
    foreach ($f in @('nvwgf2umx.dll', 'nvapi64.dll', 'nvEncodeAPI64.dll', 'nvcuda.dll', 'nvml.dll', 'nvlddmkm.sys')) {
        $p = Join-Path 'C:\Windows\System32' $f
        if (Test-Path $p) {
            $sz = [math]::Round((Get-Item $p).Length / 1MB, 1)
            Write-Host "  EXISTS: $f ($sz MB)"
        } else {
            Write-Host "  MISSING: $f"
        }
    }
}
