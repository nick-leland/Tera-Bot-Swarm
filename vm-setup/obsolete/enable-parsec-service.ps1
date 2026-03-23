$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Kill existing parsecd
    Stop-Process -Name parsecd -Force -ErrorAction SilentlyContinue
    Stop-Process -Name pservice -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Remove parsecd from Run key - pservice will inject it
    Remove-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'Parsec' -ErrorAction SilentlyContinue
    Remove-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'Parsec.App.0' -ErrorAction SilentlyContinue
    Write-Host 'Removed parsecd from Run key'

    # Write config.json with app_run_level: 1 (service mode), no BOM
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $obj = @(
        'See https://parsec.app/config for documentation and example. JSON must be valid before saving or file be will be erased.',
        [ordered]@{
            app_changelog_ver = [ordered]@{ value = 8 }
            app_channel       = [ordered]@{ value = 'release17' }
            app_run_level     = [ordered]@{ value = 1 }
            app_auto_update   = [ordered]@{ value = 0 }
        }
    )
    $json = $obj | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText('C:\Users\bot\AppData\Roaming\Parsec\config.json', $json, $utf8NoBom)
    Write-Host 'config.json set to app_run_level: 1 (service mode)'

    # Enable and configure pservice
    $svc = Get-Service -Name 'Parsec' -ErrorAction SilentlyContinue
    if ($svc) {
        Set-Service -Name 'Parsec' -StartupType Automatic
        Start-Service -Name 'Parsec' -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        Write-Host "Parsec service status: $((Get-Service 'Parsec').Status)"
    } else {
        Write-Host 'ERROR: Parsec service not found!'
    }

    # Verify Run key is clean
    Write-Host '=== Run key ==='
    Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
}
