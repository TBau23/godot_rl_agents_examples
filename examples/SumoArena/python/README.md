# Sumo RL Training

## Setup (one-time)

```bash
cd python
source venv/bin/activate
```

## Training

### Quick test (with visualization)

**Terminal 1 - Python (start first):**
```bash
cd /Users/tombauer/workspace/github.com/TBau23/gauntlet/uncharted/sumo-rl/python
source venv/bin/activate
python train.py --timesteps 10000 --viz
```
Wait until you see `waiting for remote GODOT connection on port 11008`

**Terminal 2 - Godot (start second):**
```bash
# Option A: Open Godot editor and press F5/Play

# Option B: Command line
/Users/tombauer/Downloads/Godot.app/Contents/MacOS/Godot --path /Users/tombauer/workspace/github.com/TBau23/gauntlet/uncharted/sumo-rl
```

### Full training (headless, faster)

**Terminal 1 - Python (start first):**
```bash
cd /Users/tombauer/workspace/github.com/TBau23/gauntlet/uncharted/sumo-rl/python
source venv/bin/activate
python train.py --timesteps 500000
```

python train.py --timesteps 100000 --n_envs 4 for multiple envs
Wait until you see `waiting for remote GODOT connection on port 11008`

**Terminal 2 - Godot headless (start second):**
```bash
/Users/tombauer/Downloads/Godot.app/Contents/MacOS/Godot --path /Users/tombauer/workspace/github.com/TBau23/gauntlet/uncharted/sumo-rl --headless
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
