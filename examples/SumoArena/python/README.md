# Sumo RL Training

## Setup (one-time)

```bash
cd /Users/tombauer/workspace/github.com/TBau23/gauntlet/godot_rl_agents_examples/examples/SumoArena/python
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## Training

### Quick test (with visualization)

**Terminal 1 - Python (start first):**
```bash
cd /Users/tombauer/workspace/github.com/TBau23/gauntlet/godot_rl_agents_examples/examples/SumoArena/python
source venv/bin/activate
python train.py --timesteps 10000 --viz
```
Wait until you see `waiting for remote GODOT connection on port 11008`

**Terminal 2 - Godot (start second):**
```bash
# Option A: Open Godot editor and press F5/Play

# Option B: Command line
/Users/tombauer/Downloads/Godot.app/Contents/MacOS/Godot --path /Users/tombauer/workspace/github.com/TBau23/gauntlet/godot_rl_agents_examples/examples/SumoArena
```

### Full training (headless, faster)

**Terminal 1 - Python (start first):**
```bash
cd /Users/tombauer/workspace/github.com/TBau23/gauntlet/godot_rl_agents_examples/examples/SumoArena/python
source venv/bin/activate
python train.py --timesteps 1000000
```
Wait until you see `waiting for remote GODOT connection on port 11008`

**Terminal 2 - Godot headless (start second):**
```bash
/Users/tombauer/Downloads/Godot.app/Contents/MacOS/Godot --path /Users/tombauer/workspace/github.com/TBau23/gauntlet/godot_rl_agents_examples/examples/SumoArena --headless
```

## Train.py Options

```
--timesteps N      Total training steps (default: 500000)
--checkpoint_freq  Save every N steps (default: 50000)
--viz              Show Godot window (slower)
--resume PATH      Resume from checkpoint
--run_name NAME    Custom run name (default: timestamp)
```

## Monitoring

View training metrics:
```bash
tensorboard --logdir python/runs/<run_name>/tensorboard
```

## Output

Models saved to `python/runs/<run_name>/`:
- `checkpoints/` - periodic saves
- `sumo_final.zip` - final model
- `tensorboard/` - training logs
