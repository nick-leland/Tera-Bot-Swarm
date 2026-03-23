#Requires -RunAsAdministrator
# =============================================================================
# 3_configure-vm.ps1 - Install all software inside the VM
#
# Prerequisites:
#   - VM is running and logged in as 'bot' (Windows install finished)
#   - place install-interception.exe in this vm-setup folder
#     (get it from the oblitum/interception GitHub releases)
#
# What this does (all via PowerShell Direct - no network config needed):
#   1. Basic Windows config (disable sleep, enable RDP, disable Windows Update noise)
#   2. Install Chocolatey, then Python 3.11, Node.js, VS Build Tools
#   3. Install Parsec (for remote visualization - bypasses Hyper-V display limitations)
#   4. Copy bot project files from host into VM
#   5. pip install -r requirements.txt + install pyinterception
#   6. npm install for radar (builds zeromq native module)
#   7. Install Interception kernel driver
#   8. Write per-VM settings (ZMQ port, etc.)
#
# After this script: reboot the VM, then log into Parsec on your host and connect to it.
# Parsec provides full GPU-accelerated display via the RTX 5090 partition.
# =============================================================================

. "$PSScriptRoot\config.ps1"

# Enable Guest Service Interface so Copy-VMFile works (VMBus file copy, no network needed)
Enable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface" -ErrorAction SilentlyContinue

# --- Wait for VM to be ready ---
Write-Host "`nWaiting for VM '$VMName' to be ready for PS Direct..." -ForegroundColor Cyan
$timeout = 300  # 5 min
$elapsed = 0
while ($elapsed -lt $timeout) {
    try {
        $result = Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock { $env:COMPUTERNAME } -ErrorAction Stop
        Write-Host "  VM is ready ($result)"
        break
    } catch {
        Write-Host "  Not ready yet, waiting 10s..."
        Start-Sleep -Seconds 10
        $elapsed += 10
    }
}
if ($elapsed -ge $timeout) {
    Write-Error "VM did not become ready within $timeout seconds. Is it running and logged in?"
    exit 1
}

$session = New-PSSession -VMName $VMName -Credential $VMCred

# =============================================================================
# STEP 1: Basic Windows configuration
# =============================================================================
Write-Host "`n[1/9] Configuring Windows..." -ForegroundColor Cyan
Invoke-Command -Session $session -ScriptBlock {

    # Disable sleep / screen timeout (bots run 24/7)
    powercfg /change standby-timeout-ac 0
    powercfg /change monitor-timeout-ac 0

    # Enable RDP for later convenience
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue

    # Disable Windows Update auto-restart (prevents mid-session reboots)
    $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    if (!(Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
    Set-ItemProperty -Path $wuPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWORD

    # Disable UAC prompts (scripts run as admin, don't want popups)
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -Name "ConsentPromptBehaviorAdmin" -Value 0 -Type DWORD

    Write-Host "  Windows configured."
}

# =============================================================================
# STEP 2: Debloat Windows 11
# =============================================================================
Write-Host "`n[2/9] Debloating Windows 11 (Win11Debloat)..." -ForegroundColor Cyan
Invoke-Command -Session $session -ScriptBlock {
    & ([scriptblock]::Create((irm "https://debloat.raphi.re/"))) -RunDefaults -Silent
    Write-Host "  Debloat complete."
}

# =============================================================================
# STEP 3: Install Chocolatey, then Python 3.11, Node.js, VS Build Tools
# =============================================================================
# winget is not available on fresh DISM-applied Windows images (arrives via Windows Update).
# Chocolatey is the reliable alternative for unattended installs.
Write-Host "`n[3/9] Installing Chocolatey + Python 3.11 + Node.js + VS Build Tools..." -ForegroundColor Cyan
Write-Host "  (This step takes 15-25 min - VS Build Tools is a large download)"

Invoke-Command -Session $session -ScriptBlock {

    # Install Chocolatey
    Write-Host "  Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

    # Reload PATH so choco is available immediately
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")

    Write-Host "  Installing Python 3.11..."
    choco install python311 -y --no-progress

    Write-Host "  Installing Node.js LTS..."
    choco install nodejs-lts -y --no-progress

    Write-Host "  Installing cmake 3.x (cmake 4.x breaks libzmq build)..."
    # Pin to 3.x - cmake 4.x removed compat with cmake_minimum_required < 3.5,
    # which libzmq uses. --allow-downgrade handles case where 4.x is already installed.
    choco install cmake --version 3.31.7 --allow-downgrade --installargs 'ADD_CMAKE_TO_PATH=System' -y --no-progress

    Write-Host "  Installing VS Build Tools with C++ workload (large download)..."
    choco install visualstudio2022buildtools -y --no-progress `
        --package-parameters "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --quiet --norestart"

    # Reload PATH so python/node are usable in subsequent steps
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")

    Write-Host "  Python: $(python --version 2>&1)"
    Write-Host "  Node:   $(node --version 2>&1)"
}

# =============================================================================
# STEP 3: Install Parsec
# =============================================================================
Write-Host "`n[4/9] Installing Parsec..." -ForegroundColor Cyan
Invoke-Command -Session $session -ScriptBlock {

    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")

    # Chocolatey's parsec package is outdated - download the installer directly
    Write-Host "  Downloading Parsec installer..."
    $parsecInstaller = "$env:TEMP\parsec-windows.exe"
    Invoke-WebRequest -Uri "https://builds.parsecgaming.com/package/parsec-windows.exe" -OutFile $parsecInstaller -UseBasicParsing
    Start-Process -FilePath $parsecInstaller -ArgumentList "/silent" -Wait

    # Set Parsec to start with Windows (needed for headless hosting)
    # Check multiple possible install locations
    $parsecCandidates = @(
        "$env:LOCALAPPDATA\Parsec\parsecd.exe",
        "$env:PROGRAMFILES\Parsec\parsecd.exe",
        "${env:PROGRAMFILES(X86)}\Parsec\parsecd.exe",
        "$env:LOCALAPPDATA\Programs\Parsec\parsecd.exe"
    )
    $parsecExe = $parsecCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($parsecExe) {
        $regRun = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        Set-ItemProperty -Path $regRun -Name "Parsec" -Value "`"$parsecExe`""
        Write-Host "  Parsec installed at: $parsecExe"
        Write-Host "  Set to auto-start."
        Write-Host "  ACTION NEEDED: After reboot, log into Parsec inside the VM once to register it as a host."
    } else {
        Write-Host "  Parsec installer ran but exe not found. Searched:" -ForegroundColor Yellow
        $parsecCandidates | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
        Write-Host "  You may need to install Parsec manually inside the VM." -ForegroundColor Yellow
    }
}

# =============================================================================
# STEP 4: Copy bot project files into VM via Copy-VMFile (Hyper-V Guest Services)
# =============================================================================
# Copy-VMFile uses VMBus directly - no network, no SMB, no credentials needed.
Write-Host "`n[5/9] Copying bot project files into VM..." -ForegroundColor Cyan

# Collect all files to copy (excluding .git, node_modules, __pycache__, .pyc)
$excludeDirs = @('.git', 'node_modules', '__pycache__')
$files = Get-ChildItem -Path $BotSourcePath -Recurse -File | Where-Object {
    $relativeParts = $_.FullName.Substring($BotSourcePath.Length).Split([IO.Path]::DirectorySeparatorChar)
    -not ($relativeParts | Where-Object { $excludeDirs -contains $_ }) -and
    $_.Extension -ne '.pyc'
}

Write-Host "  Copying $($files.Count) files to C:\tera_project in VM..."
$i = 0
foreach ($file in $files) {
    $relativePath = $file.FullName.Substring($BotSourcePath.Length).TrimStart('\')
    $destPath = "C:\tera_project\$relativePath"
    Copy-VMFile -Name $VMName -SourcePath $file.FullName -DestinationPath $destPath `
        -CreateFullPath -FileSource Host -Force
    $i++
    if ($i % 50 -eq 0) { Write-Host "  ... $i / $($files.Count) files" }
}
Write-Host "  Project files copied to C:\tera_project"

# =============================================================================
# STEP 4: Python dependencies
# =============================================================================
Write-Host "`n[6/9] Installing Python dependencies..." -ForegroundColor Cyan
Invoke-Command -Session $session -ScriptBlock {

    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")

    Set-Location "C:\tera_project\tera_bot"

    Write-Host "  Running pip install -r requirements.txt..."
    python -m pip install --upgrade pip
    python -m pip install -r requirements.txt

    # Install pyinterception from the local source
    Write-Host "  Installing pyinterception..."
    Set-Location "C:\tera_project\general_tera\pyinterception"
    python -m pip install -e .

    Write-Host "  Python dependencies done."
}

# =============================================================================
# STEP 5: Node.js dependencies (builds zeromq native module)
# =============================================================================
Write-Host "`n[7/9] Installing Node.js dependencies for radar..." -ForegroundColor Cyan
Invoke-Command -Session $session -ScriptBlock {

    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")

    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")

    Set-Location "C:\tera_project\radar"

    Write-Host "  Running npm install..."
    # Skip postinstall script (electron-rebuild) - we'll run it manually with explicit version
    npm install --ignore-scripts

    # Patch zeromq module.h: MSVC 14.40+ dropped chrono_literals from non-C++17 mode.
    # Remove the using namespace and replace Xms literals with explicit std::chrono::milliseconds(X).
    $modulePath = ".\node_modules\zeromq\src\module.h"
    if (Test-Path $modulePath) {
        $content = Get-Content $modulePath -Raw
        $patched = $content `
            -replace 'using namespace std::(?:literals::)?chrono_literals;\s*\r?\n', '' `
            -replace '(\d+)ms\b', 'std::chrono::milliseconds($1)'
        if ($patched -ne $content) {
            Set-Content $modulePath $patched -NoNewline -Encoding UTF8
            Write-Host "  Patched module.h for MSVC chrono compatibility."
        } else {
            Write-Host "  module.h already patched or not found." -ForegroundColor Yellow
        }
    }

    Write-Host "  Rebuilding zeromq for Electron 11.0.5..."
    # electron-rebuild needs the version passed explicitly when electron isn't installed as a package
    & ".\node_modules\.bin\electron-rebuild.cmd" -f -w zeromq --version 11.0.5

    Write-Host "  Node dependencies done."
}

# =============================================================================
# STEP 6: Interception kernel driver
# =============================================================================
Write-Host "`n[8/9] Installing Interception driver..." -ForegroundColor Cyan

$interceptInstaller = "$PSScriptRoot\install-interception.exe"
if (!(Test-Path $interceptInstaller)) {
    Write-Host "  SKIPPED: install-interception.exe not found in vm-setup folder." -ForegroundColor Yellow
    Write-Host "  Download it from the oblitum/interception GitHub releases and place it in:"
    Write-Host "  $PSScriptRoot"
    Write-Host "  Then re-run this script (it will skip already-completed steps)."
} else {
    # Copy installer directly via VMBus (no SMB needed)
    Copy-VMFile -Name $VMName -SourcePath $interceptInstaller `
        -DestinationPath "C:\install-interception.exe" -CreateFullPath -FileSource Host -Force
    Write-Host "  Installer copied to VM."

    Invoke-Command -Session $session -ScriptBlock {
        Write-Host "  Running interception installer..."
        Start-Process -FilePath "C:\install-interception.exe" -ArgumentList "/install" -Wait -Verb RunAs
        Write-Host "  Interception driver installed. A reboot will be required."
    }
}

# =============================================================================
# STEP 7: Write bot settings for this VM
# =============================================================================
Write-Host "`n[9/9] Writing VM-specific settings..." -ForegroundColor Cyan

$zmqPort = $ZMQPort

Invoke-Command -Session $session -ScriptBlock {
    param($port)

    # Update radar ZMQ port in package.json / config
    $settingsPath = "C:\tera_project\tera_bot\settings.json"
    if (Test-Path $settingsPath) {
        $settings = Get-Content $settingsPath | ConvertFrom-Json
        # Add/update zmq_port if the field exists or is expected
        if ($settings.PSObject.Properties.Name -contains "zmq_port") {
            $settings.zmq_port = $port
            $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath
            Write-Host "  ZMQ port set to $port in settings.json"
        } else {
            Write-Host "  Note: zmq_port not found in settings.json - set it manually if needed."
        }
    }

    # Set TERA game path environment variable for the bot
    [System.Environment]::SetEnvironmentVariable("TERA_PATH", "D:\TERA Starscape", "Machine")

} -ArgumentList $zmqPort

Remove-PSSession $session

Write-Host ""
Write-Host "Configuration complete." -ForegroundColor Green
if (Test-Path "$PSScriptRoot\install-interception.exe") {
    Write-Host "Reboot the VM before running the bot (required for Interception driver)."
    Write-Host "After reboot: connect via RDP (port 3389) or Hyper-V console and launch the bot."
} else {
    Write-Host "Still needed: install Interception driver (see step 6 note above)."
}
