#!/usr/bin/env python3
"""Verify that all required packages are installed correctly."""

def main():
    print("Testing Python training environment...\n")

    # Test godot-rl
    try:
        from godot_rl.wrappers.stable_baselines_wrapper import StableBaselinesGodotEnv
        print("✓ godot-rl: OK")
    except ImportError as e:
        print(f"✗ godot-rl: FAILED - {e}")

    # Test stable-baselines3
    try:
        from stable_baselines3 import PPO
        print("✓ stable-baselines3: OK")
    except ImportError as e:
        print(f"✗ stable-baselines3: FAILED - {e}")

    # Test tensorboard
    try:
        import tensorboard
        print(f"✓ tensorboard: OK (v{tensorboard.__version__})")
    except ImportError as e:
        print(f"✗ tensorboard: FAILED - {e}")

    # Test torch
    try:
        import torch
        print(f"✓ PyTorch: OK (v{torch.__version__})")

        # Check for GPU/MPS support
        if torch.cuda.is_available():
            print(f"  → CUDA available: {torch.cuda.get_device_name(0)}")
        elif torch.backends.mps.is_available():
            print("  → MPS (Apple Silicon) available")
        else:
            print("  → CPU only (no GPU acceleration)")
    except ImportError as e:
        print(f"✗ PyTorch: FAILED - {e}")

    # Test numpy
    try:
        import numpy as np
        print(f"✓ numpy: OK (v{np.__version__})")
    except ImportError as e:
        print(f"✗ numpy: FAILED - {e}")

    print("\nEnvironment setup complete!")

if __name__ == "__main__":
    main()
