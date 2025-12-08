#!/usr/bin/env python3
"""
Sumo RL Training Script

Trains two agents to compete in sumo-style matches using self-play.
Both agents share the same policy weights via godot_rl_agents.
"""

import os
import argparse
from datetime import datetime

from godot_rl.wrappers.stable_baselines_wrapper import StableBaselinesGodotEnv
from stable_baselines3 import PPO
from stable_baselines3.common.callbacks import CheckpointCallback
from stable_baselines3.common.vec_env import VecMonitor


def parse_args():
    parser = argparse.ArgumentParser(description="Train Sumo RL agents")
    parser.add_argument(
        "--timesteps",
        type=int,
        default=500_000,
        help="Total training timesteps (default: 500000)",
    )
    parser.add_argument(
        "--n_envs",
        type=int,
        default=1,
        help="Number of parallel environments (default: 1)",
    )
    parser.add_argument(
        "--checkpoint_freq",
        type=int,
        default=25_000,
        help="Save checkpoint every N steps (default: 25000)",
    )
    parser.add_argument(
        "--viz",
        action="store_true",
        help="Enable visualization (slower, for debugging)",
    )
    parser.add_argument(
        "--resume",
        type=str,
        default=None,
        help="Path to model to resume training from",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed (default: 42)",
    )
    parser.add_argument(
        "--run_name",
        type=str,
        default=None,
        help="Custom run name (default: timestamp)",
    )
    return parser.parse_args()


def make_env(n_envs: int = 1, viz: bool = True, seed: int = 42):
    """Create the Godot environment wrapped for Stable Baselines3."""
    env = StableBaselinesGodotEnv(
        env_path=None,  # None = connect to already running Godot instance
        show_window=viz,
        n_parallel=n_envs,
        seed=seed,
    )
    # VecMonitor adds episode statistics (rewards, lengths)
    return VecMonitor(env)


def main():
    args = parse_args()

    # Create run directory
    if args.run_name:
        run_name = args.run_name
    else:
        run_name = datetime.now().strftime("%Y%m%d_%H%M%S")

    run_dir = os.path.join(os.path.dirname(__file__), "runs", run_name)
    checkpoint_dir = os.path.join(run_dir, "checkpoints")
    tensorboard_dir = os.path.join(run_dir, "tensorboard")

    os.makedirs(checkpoint_dir, exist_ok=True)
    os.makedirs(tensorboard_dir, exist_ok=True)

    print("=" * 50)
    print("Sumo RL Training")
    print("=" * 50)
    print(f"Run name:      {run_name}")
    print(f"Timesteps:     {args.timesteps:,}")
    print(f"Environments:  {args.n_envs}")
    print(f"Checkpoints:   every {args.checkpoint_freq:,} steps")
    print(f"Visualization: {args.viz}")
    print(f"Output dir:    {run_dir}")
    print("=" * 50)

    # Create environment
    print("\nConnecting to Godot...")
    print("(Make sure Godot is running with the training_arena scene)")
    env = make_env(n_envs=args.n_envs, viz=args.viz, seed=args.seed)
    print(f"Connected! Observation space: {env.observation_space}")
    print(f"           Action space: {env.action_space}")

    # Create or load model
    if args.resume:
        print(f"\nResuming from: {args.resume}")
        model = PPO.load(args.resume, env=env)
        model.tensorboard_log = tensorboard_dir
    else:
        print("\nCreating new PPO model...")
        model = PPO(
            policy="MultiInputPolicy",  # Required for Dict observation space
            env=env,
            verbose=1,
            # Learning parameters
            learning_rate=3e-4,
            n_steps=2048,  # Steps per environment before update
            batch_size=64,
            n_epochs=10,  # Gradient updates per batch
            # Discount and advantage
            gamma=0.99,
            gae_lambda=0.95,
            # PPO specific
            clip_range=0.2,
            ent_coef=0.01,  # Entropy bonus for exploration
            # Logging
            tensorboard_log=tensorboard_dir,
            # Note: seed not passed - godot_rl doesn't support env.seed()
        )

    # Checkpoint callback
    # save_freq is in rollout steps (calls to _on_step), not raw timesteps
    # With PPO n_steps=2048, each _on_step = 2048 timesteps
    # So we divide by n_steps to get the desired checkpoint frequency
    n_steps = 2048  # Must match PPO n_steps above
    checkpoint_rollouts = max(1, args.checkpoint_freq // n_steps)
    print(f"Checkpoint frequency: every {args.checkpoint_freq:,} steps (~{checkpoint_rollouts} rollouts)")
    print(f"Checkpoint dir: {checkpoint_dir}")

    checkpoint_callback = CheckpointCallback(
        save_freq=checkpoint_rollouts,
        save_path=checkpoint_dir,
        name_prefix="sumo_ppo",
        save_replay_buffer=False,
        save_vecnormalize=False,
        verbose=1,
    )

    # Train!
    print("\nStarting training...")
    print("(Use Ctrl+C to stop early - model will be saved)")
    print("-" * 50)

    try:
        model.learn(
            total_timesteps=args.timesteps,
            callback=checkpoint_callback,
            progress_bar=True,
            reset_num_timesteps=args.resume is None,
        )
    except KeyboardInterrupt:
        print("\n\nTraining interrupted by user.")

    # Save final model
    final_path = os.path.join(run_dir, "sumo_final")
    model.save(final_path)
    print(f"\nFinal model saved to: {final_path}.zip")

    # Print TensorBoard instructions
    print("\n" + "=" * 50)
    print("Training complete!")
    print("=" * 50)
    print(f"\nTo view training metrics:")
    print(f"  tensorboard --logdir {tensorboard_dir}")
    print(f"\nTo resume training:")
    print(f"  python train.py --resume {final_path}")

    env.close()


if __name__ == "__main__":
    main()
