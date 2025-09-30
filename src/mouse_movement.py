"""The Goal of this file is to test the mouse movement of the character to entities found in radar."""
import json
import zmq
import time
import interception
from interception_commands import zoom_out


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
        with open('player_rotation.txt', 'w') as f:
            f.write(str(data['player']['rotation']))


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

    # Basic Game Initialization
    while True:
        try:
            message = radar_socket.recv_string(zmq.NOBLOCK)
        except zmq.error.Again:
            time.sleep(0.01)
            continue

        if message:
            # Intiial Game Setup
            interception.press("esc")
            time.sleep(0.1)
            zoom_out()
            time.sleep(0.1)

            # Mouse Calibration
            mouse_calibration(10, 10, radar_socket)
            print("Mouse Calibration Complete")
            break
