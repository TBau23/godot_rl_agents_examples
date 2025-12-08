#!/usr/bin/env python3
"""
Lightweight ONNX inference server for Godot.

Loads a trained model and responds to inference requests over TCP socket.
This allows GDScript Godot (without C# support) to use trained models.

Usage:
    python inference_server.py --model runs/YYYYMMDD_HHMMSS/sumo_model.onnx

The server listens on localhost:11100 and expects JSON messages:
    Request:  {"obs": [15 floats]}
    Response: {"actions": {"move": [...], "turn": [...], "charge": N, ...}}
"""

import argparse
import json
import socket
import threading
from pathlib import Path

import numpy as np
import onnxruntime as ort


class InferenceServer:
    def __init__(self, model_path: str, host: str = "127.0.0.1", port: int = 11100):
        self.host = host
        self.port = port

        # Load ONNX model
        print(f"Loading model from {model_path}...")
        self.session = ort.InferenceSession(model_path)
        self.input_name = self.session.get_inputs()[0].name
        print(f"Model loaded! Input: {self.input_name}")

        self.server_socket = None
        self.running = False

    def run_inference(self, obs: list) -> dict:
        """Run inference on observation, return action dict."""
        obs_array = np.array([obs], dtype=np.float32)
        outputs = self.session.run(None, {self.input_name: obs_array})
        action_array = outputs[0][0]  # First output, first batch

        # Model outputs 5 values (action means only):
        # [0] move (continuous, -1 to 1)
        # [1] turn (continuous, -1 to 1)
        # [2] charge (discrete, threshold at 0)
        # [3] swing_left (discrete, threshold at 0)
        # [4] swing_right (discrete, threshold at 0)

        actions = {
            "move": [float(np.clip(action_array[0], -1.0, 1.0))],
            "turn": [float(np.clip(action_array[1], -1.0, 1.0))],
            "charge": 1 if action_array[2] > 0 else 0,
            "swing_left": 1 if action_array[3] > 0 else 0,
            "swing_right": 1 if action_array[4] > 0 else 0,
        }

        return actions

    def handle_client(self, client_socket: socket.socket, addr):
        """Handle a single client connection."""
        print(f"Client connected: {addr}")
        buffer = ""

        try:
            while self.running:
                data = client_socket.recv(4096)
                if not data:
                    break

                buffer += data.decode('utf-8')

                # Process complete JSON messages (newline-delimited)
                while '\n' in buffer:
                    line, buffer = buffer.split('\n', 1)
                    if not line.strip():
                        continue

                    try:
                        request = json.loads(line)

                        if request.get("type") == "inference":
                            obs = request.get("obs", [])
                            actions = self.run_inference(obs)
                            response = {"type": "actions", "actions": actions}
                        elif request.get("type") == "ping":
                            response = {"type": "pong"}
                        else:
                            response = {"type": "error", "message": "Unknown request type"}

                        client_socket.send((json.dumps(response) + '\n').encode('utf-8'))

                    except json.JSONDecodeError as e:
                        error_response = {"type": "error", "message": f"Invalid JSON: {e}"}
                        client_socket.send((json.dumps(error_response) + '\n').encode('utf-8'))

        except Exception as e:
            print(f"Client error: {e}")
        finally:
            print(f"Client disconnected: {addr}")
            client_socket.close()

    def start(self):
        """Start the server."""
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind((self.host, self.port))
        self.server_socket.listen(5)
        self.server_socket.settimeout(1.0)  # Allow checking self.running
        self.running = True

        print(f"\n{'='*50}")
        print(f"Inference Server Running")
        print(f"{'='*50}")
        print(f"Host: {self.host}:{self.port}")
        print(f"Waiting for Godot to connect...")
        print(f"Press Ctrl+C to stop")
        print(f"{'='*50}\n")

        try:
            while self.running:
                try:
                    client_socket, addr = self.server_socket.accept()
                    client_thread = threading.Thread(
                        target=self.handle_client,
                        args=(client_socket, addr),
                        daemon=True
                    )
                    client_thread.start()
                except socket.timeout:
                    continue
        except KeyboardInterrupt:
            print("\nShutting down...")
        finally:
            self.running = False
            self.server_socket.close()


def main():
    parser = argparse.ArgumentParser(description="ONNX Inference Server for Godot")
    parser.add_argument(
        "--model",
        type=str,
        default="runs/20251207_011806/sumo_model.onnx",
        help="Path to ONNX model file",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=11100,
        help="Port to listen on (default: 11100)",
    )
    args = parser.parse_args()

    model_path = Path(args.model)
    if not model_path.exists():
        # Try relative to script directory
        script_dir = Path(__file__).parent
        model_path = script_dir / args.model
        if not model_path.exists():
            print(f"Error: Model not found at {args.model}")
            return

    server = InferenceServer(str(model_path), port=args.port)
    server.start()


if __name__ == "__main__":
    main()
