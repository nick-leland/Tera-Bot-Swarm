$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $store = 'C:\Windows\System32\HostDriverStore\FileRepository'

    foreach ($folder in @('nv_dispi.inf_amd64_4bf4c17fa8a478b5', 'nv_dispi.inf_amd64_6d8eaa80a18aada4')) {
        $infPath = Join-Path $store "$folder\nv_dispi.inf"
        if (!(Test-Path $infPath)) { Write-Host "NOT FOUND: $infPath"; continue }

        Write-Host "=== $folder ==="
        $content = Get-Content $infPath

        # Lines mentioning VEN_1414
        Write-Host '--- VEN_1414 lines ---'
        $content | Select-String 'VEN_1414' | ForEach-Object { Write-Host "  $($_.Line)" }

        # Lines mentioning DEV_008E
        Write-Host '--- DEV_008E lines ---'
        $content | Select-String 'DEV_008E' | ForEach-Object { Write-Host "  $($_.Line)" }

        # First 20 lines
        Write-Host '--- First 20 lines ---'
        $content | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
    }

    Write-Host '=== Current bound driver for NVIDIA GPU-P ==='
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' } |
        Select-Object InstanceId, Status | Format-List

    Write-Host '=== pnputil enum all display class drivers ==='
    pnputil /enum-drivers /class Display 2>&1 | Select-Object -First 60
}
