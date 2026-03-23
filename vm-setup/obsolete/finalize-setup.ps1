$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {

    # 1. Update Fix-NVIDIA-GPU script to retry up to 5 times with longer waits
    $fixScript = @'
$log = 'C:\Windows\Temp\nvidia-fix.log'
"[{0}] Starting NVIDIA fix script" -f (Get-Date) | Out-File $log -Append

# Ensure VirtualRender is running
$svc = Get-Service -Name 'VirtualRender' -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -ne 'Running') {
    Start-Service -Name 'VirtualRender' -ErrorAction SilentlyContinue
}
for ($i = 0; $i -lt 10; $i++) {
    if ((Get-Service 'VirtualRender' -ErrorAction SilentlyContinue).Status -eq 'Running') { break }
    Start-Sleep -Seconds 3
}
("VirtualRender status: {0}" -f (Get-Service 'VirtualRender').Status) | Out-File $log -Append

# Retry NVIDIA fix up to 5 times
for ($attempt = 1; $attempt -le 5; $attempt++) {
    $nvidia = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' }
    ("NVIDIA status (attempt $attempt): {0}" -f $nvidia.Status) | Out-File $log -Append
    if ($nvidia -and $nvidia.Status -eq 'OK') {
        "NVIDIA OK, no fix needed" | Out-File $log -Append
        break
    }
    if ($nvidia) {
        "Fixing NVIDIA Code 43: disabling device" | Out-File $log -Append
        Disable-PnpDevice -InstanceId $nvidia.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        Enable-PnpDevice -InstanceId $nvidia.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 8
        $nvidia = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' }
        ("NVIDIA status after fix attempt $attempt): {0}" -f $nvidia.Status) | Out-File $log -Append
        if ($nvidia.Status -eq 'OK') { break }
    }
    Start-Sleep -Seconds 5
}
'@
    [System.IO.File]::WriteAllText('C:\Windows\fix-nvidia-gpu.ps1', $fixScript, [System.Text.Encoding]::UTF8)
    Write-Host 'Updated fix-nvidia-gpu.ps1 with 5-retry logic'

    # 2. Verify scheduled task still present
    $task = Get-ScheduledTask -TaskName 'StartParsecAtLogon' -ErrorAction SilentlyContinue
    if ($task) {
        Write-Host "StartParsecAtLogon task: $($task.State)"
    } else {
        Write-Host 'WARNING: StartParsecAtLogon task missing - recreating'
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument '-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Users\bot\launch-parsec.ps1'
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User 'bot'
        $principal = New-ScheduledTaskPrincipal -UserId 'bot' -LogonType Interactive -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 24) -AllowStartIfOnBatteries
        Register-ScheduledTask -TaskName 'StartParsecAtLogon' -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
        Write-Host 'Recreated StartParsecAtLogon'
    }

    # 3. Verify Fix-NVIDIA-GPU task
    $fixTask = Get-ScheduledTask -TaskName 'Fix-NVIDIA-GPU' -ErrorAction SilentlyContinue
    Write-Host "Fix-NVIDIA-GPU task: $($fixTask.State)"

    # 4. Optimize Parsec config: add host_fps=60, encoder_bitrate=20 for better quality
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $obj = @(
        'See https://parsec.app/config for documentation and example. JSON must be valid before saving or file be will be erased.',
        [ordered]@{
            app_block_hash    = [ordered]@{ value = 'b4e1daaee72eb9ea621918eaa4293a50bcf9c4d71fb545325b7dcd8b0e858f34' }
            app_run_level     = [ordered]@{ value = 0 }
            encoder_bitrate   = [ordered]@{ value = 20 }
            host_fps          = [ordered]@{ value = 30 }
        }
    )
    $json = $obj | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText('C:\Users\bot\AppData\Roaming\Parsec\config.json', $json, $utf8NoBom)
    Write-Host 'Parsec config updated: 20 Mbps bitrate, 30 FPS target'

    # 5. Verify VirtualRender is Automatic
    Set-Service 'VirtualRender' -StartupType Automatic -ErrorAction SilentlyContinue
    Write-Host "VirtualRender startup: $((Get-Service 'VirtualRender').StartType)"

    # 6. Check auto-logon is configured
    $autologon = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue
    Write-Host "AutoAdminLogon: $($autologon.AutoAdminLogon), DefaultUserName: $($autologon.DefaultUserName)"

    # 7. Show final state summary
    Write-Host '=== FINAL STATE ==='
    Write-Host "NVIDIA: $((Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA GeForce*' }).Status)"
    Write-Host "VirtualRender: $((Get-Service 'VirtualRender').Status)"
    Write-Host "Parsec service: $((Get-Service 'Parsec').Status) / $((Get-Service 'Parsec').StartType)"
    Get-Content 'C:\Users\bot\launch-parsec.ps1'
}
