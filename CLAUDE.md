# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a comprehensive TERA MMORPG modding and automation framework. This is a monorepo containing:

1. **packet-logger** - Network packet logging and analysis tool
2. **radar** - Real-time entity tracking system via ZeroMQ messaging
3. **tera_bot** - Python-based bot automation scripts
4. **vm-setup** - PowerShell scripts for managing the TeraBot1 Hyper-V VM

> **Note:** `general_tera` (TERA Toolbox, pyinterception, etc.) lives outside this repo at `../general_tera/` on the host machine.

## Key Commands

### TERA Toolbox (external to this repo)
```bash
# Run with GUI (recommended)
cd ../general_tera/tera-toolbox
./TeraToolbox.exe

# Install a module
# Place module in ../general_tera/tera-toolbox/mods/ directory
```

### Radar Module
```bash
# Build for Electron 11.0.5 (required for TERA Toolbox compatibility)
cd radar
npm install
npm run build

# Test ZeroMQ publisher
node test-zeromq.js

# Run Python client
python client.py
```

### Python Bot
```bash
cd tera_bot
# Install dependencies
pip install -r requirements.txt

# Run main bot
python main.py

# Run specific components
python bot.py
python mouse_movement.py
```

### Packet Logger
```bash
# In-game commands (when TERA Toolbox is running)
/packetlogger start      # Start logging
/packetlogger stop       # Stop logging
/packetlogger status     # Check status
/packetlogger clear      # Clear logs
```

### VM Setup
```bash
cd vm-setup
# Run scripts in order on the Hyper-V host (PowerShell as admin)
./1_host-setup.ps1
./2_create-vm.ps1
./3_configure-vm.ps1
./4_setup-gpu.ps1
```

## Architecture

### Module System
- TERA Toolbox serves as the main framework hosting all modules
- Modules are placed in `../general_tera/tera-toolbox/mods/` directory
- Each module requires a `module.json` manifest file
- Modules hook into game packets using the TERA Toolbox API

### Inter-Process Communication
- **Radar** uses ZeroMQ publisher on port 3000 to stream entity data
- **tera_bot** can consume radar data via Python ZeroMQ client
- Data format: JSON with player positions, entity data, distances, HP

### Packet Processing Pipeline
1. TERA Toolbox intercepts game packets
2. Modules can hook, modify, or block packets
3. packet-logger can capture all traffic for analysis
4. Packets identified by numeric opcodes (translated via opcode maps)

## Development Notes

### JavaScript Modules (TERA Toolbox)
- Node.js version requirement: >=11.4.0
- Module entry point: `index.js`
- Access game state via `mod.game` API
- Hook packets: `mod.hook('PACKET_NAME', version, handler)`
- Send packets: `mod.send('PACKET_NAME', version, data)`

### Python Components
- **pyinterception**: Low-level input simulation without injection flags (in `../general_tera/pyinterception/`)
- **tera_bot**: Uses interception for human-like input simulation
- Configuration files: `settings.json`, `entities.json`, `game-data.json`

### Native Build Requirements
- **radar**: Requires C++ build tools for ZeroMQ native bindings
- **pyinterception**: Requires C++ compiler for native modules
- Use `electron-rebuild` for Electron compatibility

### Important Configuration Files
- `packet-logger/blacklist.json` - Filtered packet opcodes
- `radar/package.json` - ZeroMQ configuration
- `tera_bot/settings.json` - Bot behavior settings
- `vm-setup/config.ps1` - VM credentials and configuration

## Module Development Guidelines

1. All TERA Toolbox modules must include a `module.json` manifest
2. Use the provided mod API for packet hooks and game state access
3. Store user settings in `mod.settings` (auto-persisted)
4. Register commands via `mod.command.add()`
5. Use `mod.log()` for debugging output
6. Follow existing code patterns in similar modules

## Testing

### Radar Testing
```bash
cd radar
node test-zeromq.js  # Publisher test
python client.py      # Consumer test
```

### Bot Calibration
```bash
cd tera_bot
python calibrate_window_reader.py  # Screen reading calibration
python test_mouse_movement.py      # Mouse movement testing
```

## Common Issues

1. **Radar build fails**: Ensure C++ build tools and Python 3.x are installed
2. **Modules not loading**: Check `module.json` format and Node.js version
3. **ZeroMQ connection issues**: Verify port 3000 is not in use
4. **Bot input not working**: Run as administrator, check interception driver
5. **VM not starting**: Check Hyper-V service, run vm-setup scripts as admin
