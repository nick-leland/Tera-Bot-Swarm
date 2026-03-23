#Requires -RunAsAdministrator
# =============================================================================
# 1_host-setup.ps1 - One-time host machine setup
# Run this once. If it says reboot required, reboot then run again to verify.
#
# Note: Uses Hyper-V's built-in "Default Switch" for VM networking (NAT, internet included).
# No custom switch needed.
# =============================================================================

. "$PSScriptRoot\config.ps1"

# --- 1. Hyper-V features ---
Write-Host "`n[1/3] Checking Hyper-V features..." -ForegroundColor Cyan

$features = @(
    "Microsoft-Hyper-V-All"
    "Microsoft-Hyper-V"
    "Microsoft-Hyper-V-Tools-All"
    "Microsoft-Hyper-V-Management-PowerShell"
)

$needsReboot = $false
foreach ($feature in $features) {
    $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue).State
    if ($state -ne "Enabled") {
        Write-Host "  Enabling $feature..."
        Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart | Out-Null
        $needsReboot = $true
    } else {
        Write-Host "  $feature - OK"
    }
}

# --- 2. GPU-P registry key ---
Write-Host "`n[2/3] Enabling GPU partitioning..." -ForegroundColor Cyan

$gpuRegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization"
if (!(Test-Path $gpuRegPath)) {
    New-Item -Path $gpuRegPath -Force | Out-Null
}
Set-ItemProperty -Path $gpuRegPath -Name "GpuPartitioningEnabled" -Value 1 -Type DWORD -Force
Write-Host "  GPU-P registry key set."

# --- 3. Verify Default Switch exists (Hyper-V creates it automatically) ---
Write-Host "`n[3/3] Checking network switch..." -ForegroundColor Cyan

$switch = Get-VMSwitch -Name $VMSwitchName -ErrorAction SilentlyContinue
if ($switch) {
    Write-Host "  '$VMSwitchName' found - OK (provides NAT internet to VMs)"
} else {
    Write-Host "  '$VMSwitchName' not found. Hyper-V may need a reboot to create it." -ForegroundColor Yellow
}

New-Item -ItemType Directory -Force -Path $VMPath | Out-Null
Write-Host "  VM folder: $VMPath"

# --- Done ---
Write-Host ""
if ($needsReboot) {
    Write-Host "REBOOT REQUIRED to finish enabling Hyper-V." -ForegroundColor Yellow
    Write-Host "After rebooting, run this script once more to verify, then run 2_create-vm.ps1"
} else {
    Write-Host "Host setup complete." -ForegroundColor Green
    Write-Host "Next step: run 2_create-vm.ps1 (as Administrator)"
}
