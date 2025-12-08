# SumoArena

A reinforcement learning sumo wrestling game built with Godot 4 and godot_rl_agents. Two agents compete to push each other off a circular platform.

## Requirements

- **Godot 4.5+** (with godot_rl_agents addon)
- **Python 3.11+**

## Quick Start

### 1. Python Setup (one-time)

```bash
cd python
python3 -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### 2. Play Modes

#### Human vs Human (Local Multiplayer)

Open the project in Godot and run `scenes/training_arena.tscn`.

| Player 1 | Player 2 |
|----------|----------|
| W/S - Forward/Back | Arrow Up/Down |
| A/D - Turn | Arrow Left/Right |
| Space - Charge | Enter - Charge |
| Q/E - Swing Left/Right | U/O - Swing Left/Right |

#### Human vs AI

Requires a trained model and the inference server.

**Terminal 1 - Start inference server:**
```bash
cd python
source venv/bin/activate
python inference_server.py --model runs/<your_run>/sumo_final.zip
```

**Terminal 2 - Run Godot:**
Open Godot and play `scenes/vs_ai.tscn`

Player 1 uses keyboard controls (WASD + Q/E), AI controls Player 2.

#### Watch AI vs AI

Use the training scene with a trained model to watch two AI agents fight.

## Training

Training uses PPO (Proximal Policy Optimization) via Stable Baselines3. Both agents share the same policy weights (self-play).

### Basic Training

**Terminal 1 - Start Python (first):**
```bash
cd python
source venv/bin/activate
python train.py --timesteps 500000
```
Wait for: `waiting for remote GODOT connection on port 11008`

**Terminal 2 - Start Godot (second):**
```bash
# With visualization (slower, good for debugging)
godot --path /path/to/SumoArena

# Headless (faster training)
godot --path /path/to/SumoArena --headless
```

### Multi-Arena Training (Faster)

Open `scenes/multi_training.tscn` instead - runs 4 arenas in parallel for ~4x faster training.

### Training Options

```
python train.py --help

--timesteps N        Total training steps (default: 500000)
--checkpoint_freq N  Save checkpoint every N steps (default: 25000)
--viz                Enable visualization in Python (slower)
--resume PATH        Resume from a saved model
--run_name NAME      Custom name for this run (default: timestamp)
--seed N             Random seed (default: 42)
```

### Monitoring Training

View live metrics with TensorBoard:
```bash
tensorboard --logdir python/runs/<run_name>/tensorboard
```

Key metrics to watch:
- `rollout/ep_rew_mean` - Average episode reward (should trend up)
- `rollout/ep_len_mean` - Episode length (shorter = faster knockouts)

## Checkpoints & Models

Training outputs are saved to `python/runs/<run_name>/`:

```
runs/<run_name>/
├── checkpoints/          # Periodic saves (sumo_ppo_25000_steps.zip, etc.)
├── tensorboard/          # Training logs
└── sumo_final.zip        # Final trained model
```

### Evaluating Checkpoints

To test a specific checkpoint visually:

1. Export to ONNX:
   ```bash
   cd python
   python export_onnx.py --model runs/<run_name>/checkpoints/sumo_ppo_100000_steps.zip
   ```

2. Run vs AI mode with the exported model (update inference_server.py path)

### Comparing Training Runs

```bash
# View multiple runs in TensorBoard
tensorboard --logdir python/runs
```

## Project Structure

```
SumoArena/
├── scenes/
│   ├── training_arena.tscn   # Single arena (training or 2-player)
│   ├── multi_training.tscn   # 4 arenas for faster training
│   ├── vs_ai.tscn            # Human vs AI mode
│   ├── sumo_agent.tscn       # Agent prefab
│   └── platform.tscn         # Arena platform
├── scripts/
│   ├── sumo_agent.gd         # Agent physics, actions, observations
│   ├── arena_manager.gd      # Episode management, win/loss detection
│   ├── sumo_ai_controller.gd # RL interface for training
│   └── inference_ai_controller.gd  # ONNX inference for vs AI mode
├── python/
│   ├── train.py              # Training script
│   ├── export_onnx.py        # Convert model to ONNX
│   ├── inference_server.py   # Serve model for vs AI mode
│   └── requirements.txt      # Python dependencies
└── addons/godot_rl_agents/   # RL plugin
```

## Game Mechanics

- **Charge**: Dash forward with increased speed and push power (1.5s cooldown)
- **Swing**: Powerful arm attack that pushes opponents sideways (2s cooldown)
- **Ring Out**: Fall off the platform to lose the round
- **Timeout**: If neither agent falls after 1000 steps, it's a draw (penalized in training)
