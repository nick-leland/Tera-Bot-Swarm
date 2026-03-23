$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Stop pservice
    Stop-Service 'Parsec' -Force -ErrorAction SilentlyContinue
    Stop-Process -Name parsecd -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Set Parsec service to Disabled (don't want it auto-starting)
    Set-Service 'Parsec' -StartupType Disabled

    # Config: standalone mode, no channel (stay on 101b), encoder hint
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $obj = @(
        'See https://parsec.app/config for documentation and example. JSON must be valid before saving or file be will be erased.',
        [ordered]@{
            app_run_level = [ordered]@{ value = 0 }
        }
    )
    $json = $obj | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText('C:\Users\bot\AppData\Roaming\Parsec\config.json', $json, $utf8NoBom)
    Write-Host 'Config set to standalone (app_run_level: 0)'

    # Add parsecd to Run key
    Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'Parsec' -Value 'C:\Program Files\Parsec\parsecd.exe'
    Write-Host 'parsecd added to Run key'

    # Disable Hyper-V Video adapter (it's competing with VDD as primary display)
    $hypervvideo = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*Hyper-V Video*' }
    Write-Host "Hyper-V Video current status: $($hypervvideo.Status)"
    if ($hypervvideo) {
        Disable-PnpDevice -InstanceId $hypervvideo.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host 'Hyper-V Video disabled'
    }

    # Verify display state
    Start-Sleep -Seconds 3
    Write-Host '=== Display adapters after disabling Hyper-V Video ==='
    Get-WmiObject Win32_VideoController | Select-Object Name, CurrentHorizontalResolution, CurrentVerticalResolution | Format-Table -AutoSize

    # Verify Run key
    Write-Host '=== Run key ==='
    Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' | Select-Object Parsec, OneDrive

    Write-Host 'Rebooting...'
    Restart-Computer -Force
}
