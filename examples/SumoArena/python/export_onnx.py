#!/usr/bin/env python3
"""Export a trained Sumo RL model to ONNX format for Godot inference.

Usage:
    python export_onnx.py --model runs/YYYYMMDD_HHMMSS/sumo_final.zip

This creates a .onnx file that can be loaded by godot_rl_agents for
inference without needing Python.
"""

import argparse
from pathlib import Path

import torch
import numpy as np
from stable_baselines3 import PPO


def main():
    parser = argparse.ArgumentParser(description="Export trained model to ONNX")
    parser.add_argument(
        "--model",
        type=str,
        required=True,
        help="Path to trained model (.zip file)",
    )
    parser.add_argument(
        "--output",
        type=str,
        default=None,
        help="Output path for .onnx file (default: same dir as model)",
    )
    args = parser.parse_args()

    # Validate model path
    model_path = Path(args.model)
    if not model_path.exists():
        print(f"Error: Model not found at {model_path}")
        return

    # Determine output path
    if args.output:
        output_path = Path(args.output)
    else:
        output_path = model_path.parent / "sumo_model.onnx"

    print("=" * 50)
    print("ONNX Export")
    print("=" * 50)
    print(f"Input:  {model_path}")
    print(f"Output: {output_path}")
    print("=" * 50)

    # Load the trained model
    print("\nLoading model...")
    model = PPO.load(model_path, device="cpu")
    print("Model loaded!")

    # Get the policy network
    policy = model.policy

    # Create dummy input matching observation space
    # Our obs space is Dict with "obs" key containing 15 floats
    obs_size = 15  # From sumo_ai_controller.gd get_obs()
    dummy_obs = torch.zeros(1, obs_size, dtype=torch.float32)

    # The policy expects a dict observation, but for ONNX export we need
    # to trace through the network. SB3 policies have different structures.
    # We'll export just the actor (action) network.

    print("\nExporting to ONNX...")

    # For PPO with MultiInputPolicy, we need to handle the dict obs
    # The policy.forward() method handles this, but for ONNX we need
    # to work with the underlying networks

    class OnnxablePolicy(torch.nn.Module):
        """Wrapper to make SB3 policy ONNX-exportable."""

        def __init__(self, policy):
            super().__init__()
            self.policy = policy

        def forward(self, obs):
            # obs is a flat tensor, wrap it in the expected dict format
            obs_dict = {"obs": obs}
            # Extract features
            features = self.policy.extract_features(obs_dict)
            if self.policy.share_features_extractor:
                latent_pi, latent_vf = self.policy.mlp_extractor(features)
            else:
                pi_features, vf_features = features
                latent_pi = self.policy.mlp_extractor.forward_actor(pi_features)
            # Get action distribution
            distribution = self.policy._get_action_dist_from_latent(latent_pi)
            # Return action means for continuous, logits for discrete
            # For our mixed action space, we return the raw outputs
            actions = distribution.mode()
            return actions

    onnx_policy = OnnxablePolicy(policy)
    onnx_policy.eval()

    # Export
    torch.onnx.export(
        onnx_policy,
        dummy_obs,
        str(output_path),
        opset_version=11,
        input_names=["obs"],
        output_names=["actions"],
        dynamic_axes={
            "obs": {0: "batch_size"},
            "actions": {0: "batch_size"},
        },
    )

    print(f"\nExported to: {output_path}")

    # Verify the export
    print("\nVerifying ONNX model...")
    import onnx
    onnx_model = onnx.load(str(output_path))
    onnx.checker.check_model(onnx_model)
    print("ONNX model is valid!")

    # Test inference
    print("\nTesting inference...")
    import onnxruntime as ort
    session = ort.InferenceSession(str(output_path))
    test_obs = np.zeros((1, obs_size), dtype=np.float32)
    outputs = session.run(None, {"obs": test_obs})
    print(f"Test output shape: {outputs[0].shape}")
    print(f"Test output: {outputs[0]}")

    print("\n" + "=" * 50)
    print("Export complete!")
    print("=" * 50)
    print(f"\nTo use in Godot:")
    print(f"  1. Copy {output_path.name} to your Godot project")
    print(f"  2. Set Sync node control_mode to ONNX_INFERENCE")
    print(f"  3. Set onnx_model_path to res://path/to/{output_path.name}")


if __name__ == "__main__":
    main()
