# Tera Radar Mod

Real-time entity tracking for TERA via ZeroMQ messaging.

## Quick Start

1. Install in TERA Toolbox mods folder
2. Start TERA and enter game
3. Connect Python client to `tcp://127.0.0.1:3000`
4. Data flows automatically every 1500ms

## Python Client

```python
import zmq
import json

socket = zmq.Context().socket(zmq.SUB)
socket.connect("tcp://127.0.0.1:3000")
socket.setsockopt(zmq.SUBSCRIBE, b"")

while True:
    message = socket.recv_string(zmq.NOBLOCK)
    if message:
        data = json.loads(message)
        print(f"Player: {data['player']['position']}")
        for entity in data['entities']:
            print(f"{entity['name']}: {entity['distance']:.1f}m")
```

## Configuration

Edit `index.js`:

```javascript
const radar_interval = 1500;  // milliseconds
const radar_radius = 1000;    // meters
```

## Data Format

```json
{
  "player": {
    "position": {"x": 123.45, "y": 67.89, "z": 12.34},
    "rotation": 1.57,
    "yaw": 1.57,
    "pitch": 0.12,
    "isActive": true
  },
  "entities": [
    {
      "name": "Goblin Scout",
      "position": {"x": 145.67, "y": 68.12, "z": 15.78},
      "distance": 23.4,
      "hp": 800,
      "maxHp": 1200
    }
  ]
}
```

## Installation

### Quick Start (Automated)
1. Copy mod to TERA Toolbox
2. Run: `node build.js` (in the radar mod directory)
3. Start TERA

### Manual Installation
1. Install dependencies: `npm install`
2. Rebuild for Electron: `npx electron-rebuild -f -w zeromq --electron-version=11.0.5`
3. Start TERA

### Prerequisites
- Python 3.x
- C++ Build Tools (Visual Studio Build Tools on Windows)
- See [INSTALL.md](INSTALL.md) for detailed instructions

**Note**: ZeroMQ requires native compilation for Electron 11.0.5 compatibility.