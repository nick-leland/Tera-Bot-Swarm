$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $store = 'C:\Windows\System32\HostDriverStore\FileRepository'

    foreach ($folder in @('nv_dispi.inf_amd64_4bf4c17fa8a478b5', 'nv_dispi.inf_amd64_6d8eaa80a18aada4')) {
        $f = Join-Path $store $folder
        if (!(Test-Path $f)) { Write-Host "NOT FOUND: $folder"; continue }
        Write-Host "=== $folder ==="
        $files = Get-ChildItem $f -ErrorAction SilentlyContinue
        Write-Host "  Total files: $($files.Count)"
        Write-Host "  nvlddmkm.sys: $(Test-Path (Join-Path $f 'nvlddmkm.sys'))"
        Write-Host "  nv_dispi.inf: $(Test-Path (Join-Path $f 'nv_dispi.inf'))"
        # List .sys files
        $files | Where-Object { $_.Extension -eq '.sys' } | Select-Object Name, Length
    }

    Write-Host '=== Host DriverStore nvlddmkm.sys ==='
    # Check if accessible from VM somehow
    $hostDS = 'C:\Windows\System32\DriverStore\FileRepository'
    if (Test-Path $hostDS) {
        Get-ChildItem $hostDS -Filter 'nv_dispi*' -Directory | ForEach-Object {
            $sys = Join-Path $_.FullName 'nvlddmkm.sys'
            if (Test-Path $sys) { Write-Host "  FOUND: $sys ($([math]::Round((Get-Item $sys).Length/1MB,1)) MB)" }
        }
    }
}
