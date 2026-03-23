# TERA AI Agent Project Plan

## Project Goal
Build an AI agent system that can autonomously control a TERA character, demonstrating modern AI/agent development skills for job applications.

## Current State Assessment

### Working Components
- **TERA Toolbox**: Framework for intercepting/modifying game packets
- **Radar Module**: Broadcasts game state via ZeroMQ (position, entities, player data)
- **Pyinterception**: Low-level input simulation without detection flags
- **Basic Bot Structure**: Character creation logic exists

### Architecture Overview
```
[TERA Game Client]
        ↓
[TERA Toolbox] → Intercepts packets
        ↓
[Radar Module] → Extracts game state
        ↓
[ZeroMQ Stream] → Port 3000, JSON format
        ↓
[Python AI Agent] → Decision making
        ↓
[Action Executor] → Translates decisions
        ↓
[Pyinterception] → Executes keyboard/mouse
        ↓
[TERA Game Client] → Receives input
```

## Development Roadmap

### Phase 1: Foundation (Week 1)
- [ ] Verify TERA Toolbox still connects to game
- [ ] Test radar module ZeroMQ broadcast
- [ ] Confirm pyinterception still works on current system
- [ ] Create simple state reader in Python to consume ZeroMQ
- [ ] Build basic action executor (WASD movement, mouse look)

### Phase 2: Basic Agent (Week 2)
- [ ] Implement state abstraction layer (raw data → GameState object)
- [ ] Create action abstraction (high-level actions → input sequences)
- [ ] Build simple rule-based agent for basic movement
- [ ] Add logging and visualization of agent decisions
- [ ] Test end-to-end: agent moves character around

### Phase 3: Combat Agent (Week 3-4)
- [ ] Extend state parsing for combat data (HP, MP, buffs, debuffs)
- [ ] Implement target selection logic
- [ ] Add skill rotation system
- [ ] Create combat state machine
- [ ] Build simple grinding bot that can farm mobs

### Phase 4: Intelligence Layer (Week 5-6)
- [ ] Integrate LLM for high-level planning (OpenAI/Anthropic API)
- [ ] Implement goal system (quests, farming routes, etc.)
- [ ] Add memory/learning component
- [ ] Create agent personality/behavior profiles
- [ ] Build performance metrics and dashboards

### Phase 5: Advanced Features (Week 7-8)
- [ ] Pathfinding and navigation
- [ ] Multi-agent coordination
- [ ] Market/trading automation
- [ ] Dungeon/raid participation
- [ ] Self-improvement through reinforcement learning

## Technical Decisions

### AI Approach: Hybrid System
1. **LLM Layer** (Claude/GPT-4): High-level strategy and planning
2. **Rule-Based Layer**: Combat rotations, movement patterns
3. **ML Layer** (Optional): Learn optimal farming routes, skill timings

### Key Technologies
- **Python 3.11+**: Main agent development
- **LangChain/LlamaIndex**: LLM orchestration
- **FastAPI**: Agent control API
- **Streamlit/Gradio**: Monitoring dashboard
- **OpenCV**: Visual state recognition (backup to packet reading)
- **Weights & Biases**: Experiment tracking

### Agent Capabilities (Priority Order)
1. **Movement**: Navigate to coordinates, follow paths
2. **Combat**: Target selection, skill usage, kiting
3. **Inventory**: Loot collection, item management
4. **Social**: Chat responses, party interactions
5. **Economy**: Trading, market analysis
6. **Questing**: Quest acceptance, objective completion

## Missing Components to Build

### Immediate Needs
1. **State Parser**: Convert ZeroMQ JSON → structured GameState
2. **Action Executor**: Map agent actions → pyinterception calls
3. **Agent Base Class**: Framework for different agent types
4. **Monitoring System**: Real-time dashboard of agent activity

### Future Components
1. **Pathfinding System**: A* or navigation mesh
2. **Memory Database**: Store game knowledge, learned patterns
3. **Training Framework**: For RL-based components
4. **Safety System**: Prevent detection, handle errors

## Targeting System Solution

### Problem Statement
- TERA uses reticle-based targeting (crosshair must be on target)
- Previous approach using W to move forward causes unwanted drift toward target
- Need to maintain crosshair lock while allowing free WASD movement

### Solution Architecture

#### Core Components
1. **TargetingSystem** (`targeting_system.py`)
   - Tracks camera state independently from player rotation
   - Calculates yaw/pitch angles to target
   - Converts angles to mouse movements (calibration: 579.5 units = 1 radian)
   - Includes predictive targeting for moving entities

2. **CombatController** (`combat_controller.py`)
   - Decouples movement from targeting completely
   - Uses strafing (A/D) and backing (S) for positioning
   - W key only used in short bursts to prevent drift
   - Maintains optimal combat range automatically

#### Key Math
```python
# Calculate world angle to target
world_angle = atan2(target.y - player.y, target.x - player.x)

# Convert to camera-relative angle
camera_yaw = world_angle - player_rotation

# Normalize to [-pi, pi]
camera_yaw = (camera_yaw + pi) % (2*pi) - pi

# Convert to mouse movement
mouse_x = camera_yaw / MOUSE_TO_RADIANS_X
```

#### Movement Strategy
- **Too Far (>100 units)**: Short W burst to approach
- **Optimal Range (30-80 units)**: Strafe with A/D
- **Too Close (<30 units)**: Back up with S
- **Never**: Hold W continuously (causes drift)

#### Implementation Status
- ✅ Targeting math and camera tracking
- ✅ Movement-targeting decoupling
- ✅ Predictive targeting for moving entities
- ⏳ Integration with live radar data
- ⏳ Testing with actual game

## Success Metrics
- Agent can autonomously grind mobs for 1+ hours
- Successfully navigate between major cities
- Complete simple quests without human intervention
- Maintain realistic human-like behavior patterns
- Generate insightful logs for portfolio demonstration

## Portfolio Demonstration Points
1. **System Design**: Clean architecture, separation of concerns
2. **AI Integration**: Modern LLM usage, prompt engineering
3. **Real-time Systems**: Low-latency decision making
4. **Computer Vision**: Game state recognition (if implemented)
5. **DevOps**: Monitoring, logging, error handling
6. **Documentation**: Clear code, architecture diagrams

## Next Steps
1. Test current components individually
2. Create minimal viable agent (just movement)
3. Incrementally add capabilities
4. Document everything for portfolio

## Open Questions
- Which TERA server/version are we targeting?
- Should we focus on PvE or PvP capabilities?
- How sophisticated should anti-detection be?
- Which class is easiest to automate initially?
- Should we build a web UI for controlling multiple agents?

## Risk Mitigation
- **Detection**: Use human-like delays, randomization
- **Game Updates**: Modular design to adapt quickly
- **Complexity**: Start simple, iterate frequently
- **Performance**: Profile early, optimize critical paths

## Resources Needed
- TERA game client (working)
- Test account/character
- API keys for LLM services
- Development machine with good CPU/RAM
- Time to reverse engineer any missing packet structures