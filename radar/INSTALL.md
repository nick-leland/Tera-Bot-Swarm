# ZeroMQ Installation for TERA Toolbox

This guide will help you install ZeroMQ with proper Electron 11.0.5 compatibility for the radar mod.

## Prerequisites

Before installing, make sure you have:

1. **Python 3.x** (required for native module compilation)
2. **C++ Build Tools**:
   - **Windows**: Visual Studio Build Tools or Visual Studio Community
   - **macOS**: Xcode Command Line Tools (`xcode-select --install`)
   - **Linux**: `build-essential` package

## Installation Methods

### Method 1: Automated Build Script (Recommended)

1. Navigate to the radar mod directory:
   ```bash
   cd "D:\TERA Starscape\TERA Starscape Toolbox\mods\radar"
   ```

2. Run the build script:
   ```bash
   node build.js
   ```

### Method 2: Manual Installation

1. Install dependencies:
   ```bash
   npm install
   ```

2. Rebuild ZeroMQ for Electron 11.0.5:
   ```bash
   npx electron-rebuild -f -w zeromq --electron-version=11.0.5
   ```

### Method 3: Force Build from Source

If the above methods fail, try building from source:

```bash
npm install --build-from-source zeromq
npx electron-rebuild -f -w zeromq --electron-version=11.0.5
```

## Verification

After installation, test that ZeroMQ works:

```bash
node -e "const zmq = require('zeromq'); console.log('ZeroMQ version:', zmq.version);"
```

## Troubleshooting

### Common Issues

1. **"Python not found"**: Install Python 3.x and ensure it's in your PATH
2. **"MSBuild not found"**: Install Visual Studio Build Tools
3. **"Permission denied"**: Run as administrator (Windows) or use `sudo` (macOS/Linux)

### Windows Specific

If you get MSBuild errors:
1. Install Visual Studio Build Tools 2019 or later
2. Run: `npm config set msvs_version 2019`
3. Try the installation again

### macOS Specific

If you get Xcode errors:
```bash
xcode-select --install
```

### Linux Specific

Install build essentials:
```bash
sudo apt-get update
sudo apt-get install build-essential python3-dev
```

## Alternative: Use Pre-built Binaries

If compilation continues to fail, you can try using pre-built binaries:

```bash
npm install zeromq@6.0.0 --target=11.0.5 --target_arch=x64 --target_platform=win32
```

## Success Indicators

When successful, you should see:
- ZeroMQ installation completes without errors
- The radar mod loads without "ERR_PACKAGE_PATH_NOT_EXPORTED" errors
- TERA Toolbox shows the mod as loaded successfully

## Getting Help

If you continue to have issues:
1. Check the error logs in TERA Toolbox
2. Verify your Python and C++ compiler installations
3. Try the alternative installation methods above
4. Check the [ZeroMQ.js documentation](https://github.com/zeromq/zeromq.js#rebuilding-for-electron) for more details
