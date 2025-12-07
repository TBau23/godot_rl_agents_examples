#!/usr/bin/env python3
"""Evaluate a trained Sumo RL model.

Usage:
    1. Start Godot with training_arena.tscn (single arena for better viewing)
    2. Run: python eval.py --model runs/YYYYMMDD_HHMMSS/sumo_final.zip
"""

import argparse
from pathlib import Path

from godot_rl.wrappers.stable_baselines_wrapper import StableBaselinesGodotEnv
from stable_baselines3 import PPO


def main():
    parser = argparse.ArgumentParser(description="Evaluate trained Sumo RL model")
    parser.add_argument(
        "--model",
        type=str,
        required=True,
        help="Path to trained model (.zip file)",
    )
    parser.add_argument(
        "--episodes",
        type=int,
        default=10,
        help="Number of episodes to run (default: 10, use 0 for infinite)",
    )
    args = parser.parse_args()

    # Validate model path
    model_path = Path(args.model)
    if not model_path.exists():
        print(f"Error: Model not found at {model_path}")
        return

    print("=" * 50)
    print("Sumo RL Evaluation")
    print("=" * 50)
    print(f"Model:    {model_path}")
    print(f"Episodes: {args.episodes if args.episodes > 0 else 'infinite'}")
    print("=" * 50)

    # Connect to Godot
    print("\nConnecting to Godot...")
    print("(Make sure Godot is running with training_arena.tscn)")

    env = StableBaselinesGodotEnv(show_window=True, speedup=1)
    print("Connected!")

    # Load trained model
    print(f"\nLoading model from {model_path}...")
    model = PPO.load(model_path, env=env)
    print("Model loaded!")

    # Run evaluation
    print("\nRunning evaluation...")
    print("-" * 50)

    episode_count = 0
    wins = {"agent1": 0, "agent2": 0, "draw": 0}

    try:
        obs = env.reset()
        while True:
            # Get action from trained policy
            action, _ = model.predict(obs, deterministic=True)
            obs, reward, done, info = env.step(action)

            if done.any():
                episode_count += 1
                # Track results (reward > 0 means that agent won)
                # Note: with self-play both agents use same policy
                print(f"Episode {episode_count} complete")

                if args.episodes > 0 and episode_count >= args.episodes:
                    break

                obs = env.reset()

    except KeyboardInterrupt:
        print("\n\nStopped by user")

    print("-" * 50)
    print(f"Completed {episode_count} episodes")
    env.close()


if __name__ == "__main__":
    main()
