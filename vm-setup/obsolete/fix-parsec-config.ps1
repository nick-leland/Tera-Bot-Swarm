$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $obj = @(
        'See https://parsec.app/config for documentation and example. JSON must be valid before saving or file be will be erased.',
        [ordered]@{
            app_changelog_ver = [ordered]@{ value = 8 }
            app_channel = [ordered]@{ value = 'release17' }
            app_run_level = [ordered]@{ value = 0 }
            app_auto_update = [ordered]@{ value = 0 }
        }
    )
    $json = $obj | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText('C:\Users\bot\AppData\Roaming\Parsec\config.json', $json, $utf8NoBom)
    $bytes = [System.IO.File]::ReadAllBytes('C:\Users\bot\AppData\Roaming\Parsec\config.json')
    Write-Host "First byte: $($bytes[0]) (should be 91 for [)"
    Get-Content 'C:\Users\bot\AppData\Roaming\Parsec\config.json'
}
