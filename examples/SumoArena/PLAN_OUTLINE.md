Sure! Here's the updated version:Looks like the computer environment isn't available right now. Here's the updated doc—you can save it as `DESIGN.md` in your project:

---

# Sumo RL Environment

## Overview

Train AI agents to push each other off a circular platform using reinforcement learning. Self-play environment where two agents compete in sumo-style matches.

## Project Structure
```
sumo-rl/
├── addons/
│   └── godot_rl_agents/          # RL plugin
├── scenes/
│   ├── training_arena.tscn       # Main training scene
│   ├── sumo_agent.tscn           # Agent scene (reusable)
│   └── platform.tscn             # The arena
├── scripts/
│   ├── sumo_agent.gd             # Agent movement/physics
│   ├── ai_controller.gd          # RL interface
│   └── arena_manager.gd          # Episode management, reset, scoring
├── models/
│   └── sumo_blob.glb             # Low-poly sumo character (optional)
└── python/
    └── train.py                  # Training script
```

## Arena

- Circular platform (disc/cylinder)
- Radius: 6.0 units (agent radius ~0.5, gives ~12 agent-widths across)
- Platform thickness: 0.5 units
- Agents spawn on opposite sides facing each other (at radius 3.0 from center)
- No walls — you fall off the edge
- Fixed camera overhead or angled to see both agents

## Agents

- Two identical agents, same policy (self-play)
- Visual: capsule (height 1.0, radius 0.5)
- Physics: CharacterBody3D with collision
- Mass: 10.0 units
- Movement force: 50.0 units (gives decent acceleration without feeling floaty)
- Max speed: 8.0 units/sec
- Turn speed: 3.0 rad/sec
- No animations needed (sliding movement is fine)

## Action Space

Continuous only (no discrete actions):
| Action | Range | Description |
|--------|-------|-------------|
| move   | -1.0 to 1.0 | backward to forward |
| turn   | -1.0 to 1.0 | left to right |

## Observation Space

| Observation          | Type  | Description |
|----------------------|-------|-------------|
| angle_to_enemy_sin   | float | sin(angle to enemy), -1.0 to 1.0 |
| angle_to_enemy_cos   | float | cos(angle to enemy), -1.0 to 1.0 |
| distance_to_enemy    | float | Normalized, 0.0 = touching, 1.0 = max arena distance |
| distance_to_edge     | float | Normalized, 0.0 = at edge, 1.0 = center |
| enemy_distance_to_edge | float | Normalized, lets agent exploit edge positioning |
| own_velocity_x       | float | Local velocity (normalized by max speed) |
| own_velocity_z       | float | Local velocity (normalized by max speed) |
| enemy_velocity_x     | float | Relative velocity (normalized) |
| enemy_velocity_z     | float | Relative velocity (normalized) |

Total: 9 floats

Note: Using sin/cos for angle avoids discontinuity when enemy is directly behind.

## Combat Mechanics

- Pure physics collision — no shove button
- Agents have mass, can push each other
- Momentum matters (running into someone pushes harder than walking)
- CharacterBody3D move_and_slide handles collision response

## Rewards

| Event                  | Reward  |
|------------------------|---------|
| Opponent falls off     | +1.0    |
| You fall off           | -1.0    |
| Per step               | -0.001  |

Zero-sum: when one agent gets +1, the other gets -1.

## Episode Termination

- One agent falls below platform (Y < -1.0)
- Timeout (max steps: 1000, ~16 seconds at 60fps)
- On timeout: draw, both get 0 reward

Note: Rewarding closest-to-center on timeout encourages camping, so we avoid it.

## Self-Play Notes

- Both agents use identical policy weights
- Both agents' experiences are added to replay buffer (learn from both perspectives)
- godot_rl_agents handles this automatically with multiple AIController3D nodes
- Periodically save checkpoints to track skill progression

## Implementation Steps

### Phase 1: Basic Scene
1. [ ] Create circular platform with collision (CylinderShape3D or CSGCylinder3D)
2. [ ] Create capsule agent with CharacterBody3D
3. [ ] Implement basic movement (forward/back, turn) with keyboard for testing
4. [ ] Spawn two agents, verify physics collision pushes them
5. [ ] Detect falling off (Y position check < -1.0)
6. [ ] Test that momentum affects push strength

### Phase 2: RL Integration
1. [ ] Install godot_rl_agents plugin
2. [ ] Add AIController3D to each agent
3. [ ] Implement get_obs() — return 9 observation floats
4. [ ] Implement get_action() — apply movement from RL
5. [ ] Implement get_reward() — track falls, assign +1/-1
6. [ ] Implement reset() — respawn agents to starting positions, reset velocities
7. [ ] Add Sync node to training_arena scene
8. [ ] Verify both agents contribute experiences

### Phase 3: Training
1. [ ] Create Python training script with StableBaselines3 (PPO)
2. [ ] Test with visualization (1-2 envs)
3. [ ] Train headless with parallel envs (8-16), monitor with TensorBoard
4. [ ] Evaluate trained model, record behavior at checkpoints

### Phase 4: Polish (Optional)
1. [ ] Replace capsules with low-poly sumo blobs
2. [ ] Add simple particle effects (dust on collision, splash on fall)
3. [ ] Add sound effects
4. [ ] Record demo video of training progression

## Validation Checkpoints

1. [ ] Two capsules in scene, can push each other with WASD/arrow keys
2. [ ] Heavier pushes (more momentum) move opponent further
3. [ ] Fall detection works, prints to console
4. [ ] godot_rl_agents plugin installed, Sync node added, no errors
5. [ ] Can run training script, agents take random actions
6. [ ] After 100k steps, agents show non-random behavior (moving toward opponent)
7. [ ] After 500k steps, agents demonstrate basic strategy (pushing toward edge)

## Tuning Parameters

Start with these, adjust based on observed behavior:

| Parameter | Initial Value | Adjust If... |
|-----------|---------------|--------------|
| Arena radius | 6.0 | Too campy → shrink, too chaotic → expand |
| Agent mass | 10.0 | Collisions too bouncy → increase |
| Move force | 50.0 | Movement too sluggish/fast |
| Max speed | 8.0 | Agents too fast to react |
| Step penalty | -0.001 | Agents too passive → increase |
| Max steps | 1000 | Episodes timing out too often → increase |

## References

- godot_rl_agents: https://github.com/edbeeching/godot_rl_agents
- godot_rl_agents custom env tutorial: https://github.com/edbeeching/godot_rl_agents/blob/main/docs/CUSTOM_ENV.md
- Hugging Face Godot RL course: https://huggingface.co/learn/deep-rl-course/unitbonus3/godotrl

## Future Extensions

- Add shove mechanic (discrete action, cooldown-based)
- Multi-agent: 4-way sumo, last one standing
- Tournament mode: agents fight bracket style, track ELO
- Asymmetric bodies: heavy vs light agents
- Terrain variants: sloped arena, icy patches, shrinking ring
- Observation variants: raycast-only (no privileged info)

