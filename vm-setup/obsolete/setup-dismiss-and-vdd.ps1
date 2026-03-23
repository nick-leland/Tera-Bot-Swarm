$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Write dismiss-parsec-error.ps1 to user profile
    $dismissScript = @'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
"@
while ($true) {
    foreach ($title in @("Graphics Failure", "Parsec - Graphics Failure", "Parsec")) {
        $dlg = [Win32]::FindWindow($null, $title)
        if ($dlg -ne [IntPtr]::Zero) {
            $btn = [Win32]::FindWindowEx($dlg, [IntPtr]::Zero, "Button", "OK")
            if ($btn -ne [IntPtr]::Zero) {
                [Win32]::PostMessage($btn, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
            }
            [Win32]::PostMessage($dlg, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        }
    }
    Start-Sleep -Seconds 2
}
'@
    [System.IO.File]::WriteAllText('C:\Users\bot\dismiss-parsec-error.ps1', $dismissScript, [System.Text.Encoding]::UTF8)
    Write-Host 'dismiss script written'

    # Create scheduled task: runs at logon of bot user in Session 1
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument '-NonInteractive -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Users\bot\dismiss-parsec-error.ps1'
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User 'bot'
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 24)
    $principal = New-ScheduledTaskPrincipal -UserId 'bot' -LogonType Interactive -RunLevel Highest

    Unregister-ScheduledTask -TaskName 'Parsec-Dismiss-Dialog' -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName 'Parsec-Dismiss-Dialog' -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
    Write-Host 'Scheduled task Parsec-Dismiss-Dialog registered'

    # Check VDD display - should be 1920x1080
    Write-Host '=== Display adapters ==='
    Get-WmiObject Win32_VideoController | Select-Object Name, CurrentHorizontalResolution, CurrentVerticalResolution | Format-Table -AutoSize

    # Parsec VDD device status
    Write-Host '=== VDD device ==='
    Get-PnpDevice | Where-Object { $_.FriendlyName -like '*Parsec*' } | Select-Object Status, FriendlyName, InstanceId
}
