$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Kill parsecd first
    Stop-Process -Name parsecd -Force -ErrorAction SilentlyContinue
    Stop-Service -Name Parsec -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Fix VirtualRender - start it
    Write-Host '=== Starting VirtualRender ==='
    Start-Service -Name 'VirtualRender' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    Get-Service -Name 'VirtualRender' | Select-Object Name, Status, StartType

    # Fix NVIDIA Code 43 - toggle it
    Write-Host '=== NVIDIA before fix ==='
    $nvidia = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' }
    Write-Host "Status: $($nvidia.Status)"

    if ($nvidia -and $nvidia.Status -ne 'OK') {
        Write-Host 'Toggling NVIDIA device...'
        Disable-PnpDevice -InstanceId $nvidia.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        Enable-PnpDevice -InstanceId $nvidia.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 8
    }

    Write-Host '=== NVIDIA after fix ==='
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' } | Select-Object Status, FriendlyName

    # Check nvidia-fix log
    Write-Host '=== nvidia-fix.log ==='
    Get-Content 'C:\Windows\Temp\nvidia-fix.log' -ErrorAction SilentlyContinue | Select-Object -Last 20

    # Set config to SERVICE mode (app_run_level: 1) + keep block hash, no release17
    Write-Host '=== Writing service-mode config ==='
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $obj = @(
        'See https://parsec.app/config for documentation and example. JSON must be valid before saving or file be will be erased.',
        [ordered]@{
            app_block_hash = [ordered]@{ value = 'b4e1daaee72eb9ea621918eaa4293a50bcf9c4d71fb545325b7dcd8b0e858f34' }
            app_run_level  = [ordered]@{ value = 1 }
        }
    )
    $json = $obj | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText('C:\Users\bot\AppData\Roaming\Parsec\config.json', $json, $utf8NoBom)
    Write-Host 'Config: service mode (1) + block hash'
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\config.json'

    # Enable Parsec service to Automatic and start it
    Write-Host '=== Starting Parsec service ==='
    Set-Service 'Parsec' -StartupType Automatic
    Start-Service 'Parsec' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 10

    Get-Service 'Parsec' | Select-Object Name, Status, StartType

    Write-Host '=== parsecd processes after service start ==='
    Get-WmiObject Win32_Process | Where-Object { $_.Name -eq 'parsecd.exe' -or $_.Name -eq 'pservice.exe' } |
        Select-Object ProcessId, SessionId, Name, CommandLine | Format-List

    Write-Host '=== Parsec log (last 30 lines) ==='
    Start-Sleep -Seconds 5
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\log.txt' -ErrorAction SilentlyContinue | Select-Object -Last 30
}
