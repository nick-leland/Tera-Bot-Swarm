$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    Write-Host "=== VEN_1414 device detail (Get-PnpDevice) ==="
    $dev = Get-PnpDevice | Where-Object { $_.InstanceId -like '*VEN_1414*' } | Select-Object -First 1
    $dev | Format-List *

    Write-Host "=== VEN_1414 device properties ==="
    Get-PnpDeviceProperty -InputObject $dev | Where-Object { $_.Data -ne $null -and $_.Data -ne '' } |
        Select-Object KeyName, Data | Format-Table -AutoSize

    Write-Host "=== New DriverStore entry ==="
    $dsPath = 'C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_3210371373e48d7f'
    if (Test-Path $dsPath) {
        Get-ChildItem $dsPath | Select-Object Name, Length | Format-Table -AutoSize
        Write-Host "--- nv_dispi.inf VEN_1414 entries ---"
        Get-Content "$dsPath\nv_dispi.inf" | Select-String 'VEN_1414|Section048' | Select-Object -First 5
    } else {
        Write-Host "DriverStore entry not found"
    }

    Write-Host "=== pnputil enum VEN_1414 device ==="
    pnputil /enum-devices /instanceid '*VEN_1414*' 2>&1

    Write-Host "=== pnputil enum drivers for VEN_1414 ==="
    pnputil /enum-drivers /class Display 2>&1 | Select-String -Pattern 'nv_dispi|VEN_1414|Published|Driver Date' -Context 0,1 | Select-Object -First 20

    Write-Host "=== VirtualRender service ==="
    Get-Service VirtualRender -ErrorAction SilentlyContinue | Select-Object Name, Status, StartType
    sc.exe qc VirtualRender 2>&1

    Write-Host "=== nvlddmkm service ==="
    Get-Service nvlddmkm -ErrorAction SilentlyContinue | Select-Object Name, Status, StartType
}
