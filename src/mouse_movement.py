"""The Goal of this file is to test the mouse movement of the character to entities found in radar."""
import json
import zmq
import time
import os
import sys
import ctypes
from interception_commands import zoom_out


DLL_DIR = r"C:\Tools\Interception\library\x64"

if not os.path.exists(os.path.join(DLL_DIR, "interception.dll")):
    sys.exit(f"interception.dll not found in {DLL_DIR}")
else:
    os.add_dll_directory(DLL_DIR)

    ctypes.WinDLL(os.path.join(DLL_DIR, "interception.dll"))

    import interception
    from interception import beziercurve

    interception.auto_capture_devices()
    curve_params = beziercurve.BezierCurveParams()


def mouse_calibration(steps: int, step_size: int, radar_socket):
    """Learn the rotation values from interception to radians (-pi to pi values)"""
    for step in range(steps):
        interception.move_relative(step_size, 0)

        # Move backwards then forwards to trigger rotation
        interception.press("s")
        time.sleep(0.1)
        interception.press("w")
        time.sleep(1)  # Wait for new Socket to Update

        try:
            message = radar_socket.recv_string(zmq.NOBLOCK)
            data = json.loads(message)
        except zmq.error.Again:
            time.sleep(0.01)
            continue
        # Write player rotation values to file
        try:
            rotation_path = 'player_rotation.txt'
            rotation_dir = os.path.dirname(rotation_path)
            if rotation_dir:
                os.makedirs(rotation_dir, exist_ok=True)
            with open(rotation_path, 'w') as f:
                f.write(str(data['player']['rotation']))
        except IOError as e:
            print(f"Error writing to player_rotation.txt: {e}")
            continue


def target_entity(player_information, entity_information, current_pitch):
    # Initial Player Information
    player_x = player_information['position']['x']
    player_y = player_information['position']['y']
    player_z = player_information['position']['z']
    player_rotation = player_information['rotation']

    # Initial Entity Information
    entity_x = entity_information['position']['x']
    entity_y = entity_information['position']['y']
    entity_z = entity_information['position']['z']

    # Horizontal Movement

    # Vertical Movement, ignore for now
    return


if __name__ == "__main__":
    # Set initial mouse movement values (These are important to reset or build on)

    # Open the ZMQ socket
    radar_socket = zmq.Context().socket(zmq.SUB)
    radar_socket.connect("tcp://127.0.0.1:3000")
    radar_socket.setsockopt(zmq.SUBSCRIBE, b"")
    print("ZMQ socket connected to TERA Radar")
    
    # Give the socket time to establish the connection
    time.sleep(0.1)

    # Basic Game Initialization
    print("Waiting for TERA Radar to start publishing data...")
    print("Make sure:")
    print("1. TERA is running and you're in-game (not character selection)")
    print("2. TERA Radar mod is enabled in TERA Toolbox")
    print("3. The mod has been built with: node build.js")
    print("4. Check TERA Toolbox console for any radar mod errors")
    print()
    
    while True:
        try:
            message = radar_socket.recv_string(zmq.NOBLOCK)
        except zmq.error.Again:
            print("No message received from TERA Radar, Waiting for message")
            time.sleep(0.01)
            continue

        if message:
            print("Message received from TERA Radar, Starting Game")

            # Intiial Game Setup
            interception.press("esc")
            time.sleep(0.1)
            zoom_out()
            time.sleep(0.1)

            # Mouse Calibration
            mouse_calibration(10, 10, radar_socket)
            print("Mouse Calibration Complete")
            break
