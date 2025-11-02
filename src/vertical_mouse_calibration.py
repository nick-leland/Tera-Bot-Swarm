"""The Goal of this file is to test the mouse movement of the character to entities found in radar."""
import json
import zmq
import time
import os
import sys
import ctypes
from interception_commands import zoom_out
import math

DLL_DIR = r"C:\Tools\Interception\library\x64"

if not os.path.exists(os.path.join(DLL_DIR, "interception.dll")):
    sys.exit(f"interception.dll not found in {DLL_DIR}")
else:
    os.add_dll_directory(DLL_DIR)

    ctypes.WinDLL(os.path.join(DLL_DIR, "interception.dll"))

    import interception
    from interception import beziercurve
    from interception import Interception
    from interception.constants import FilterKeyFlag
    from interception import inputs  # optional, used here for auto_capture_devices

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
            rotation_path = f'player_rotation_{step}.txt'
            rotation_dir = os.path.dirname(rotation_path)
            if rotation_dir:
                os.makedirs(rotation_dir, exist_ok=True)
            with open(rotation_path, 'w') as f:
                f.write(str(data['player']['rotation']))
        except IOError as e:
            print(f"Error writing to player_rotation.txt: {e}")
            continue


def radians_to_interception_movement(angle):
    return int(angle * 579.5)


# Only X position for now
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
    directional_vector = (entity_x - player_x, entity_y - player_y)
    angle = math.atan2(directional_vector[1], directional_vector[0])
    target_angle = angle - player_rotation
    print(f"Player Position: {player_x}, {player_y}, {player_z} {player_rotation}")
    print(f"Entity Position: {entity_x}, {entity_y}, {entity_z}")
    print(f"Target Angle: {target_angle}")
    normalized_target_angle = (target_angle + math.pi) % (2 * math.pi) - math.pi
    print(f"Normalized Target Angle: {normalized_target_angle}")
    interception_movement = radians_to_interception_movement(normalized_target_angle)
    print(f"Interception Movement: {interception_movement}")
    # Vertical Movement, ignore for now

    return interception_movement


if __name__ == "__main__":
    # Set initial mouse movement values (These are important to reset or build on)

    # Open the ZMQ socket
    radar_socket = zmq.Context().socket(zmq.SUB)
    # Ensure we always process the most recent state and don't accumulate stale messages
    try:
        radar_socket.setsockopt(zmq.CONFLATE, 1)
    except Exception:
        pass  # Fallback if CONFLATE is unsupported in the current environment
    try:
        radar_socket.setsockopt(zmq.RCVHWM, 1)
    except Exception:
        pass
    # Faster reconnect behavior if publisher restarts or pauses
    try:
        radar_socket.setsockopt(zmq.RECONNECT_IVL, 200)
    except Exception:
        pass
    try:
        radar_socket.setsockopt(zmq.RECONNECT_IVL_MAX, 2000)
    except Exception:
        pass
    # Use a receive timeout so transient gaps don't force re-initialization
    try:
        radar_socket.setsockopt(zmq.RCVTIMEO, 2000)
    except Exception:
        pass
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

    waiting = False
    has_initialized = False
    has_locked_target = False
    should_exit = False

    while True:
        if should_exit:
            break

        try:
            # Blocking receive with timeout (RCVTIMEO). With CONFLATE, this is always the latest state.
            message = radar_socket.recv_string()
        except zmq.error.Again:
            if not waiting:
                print("No message received from TERA Radar, Waiting for message")
                waiting = True
            time.sleep(0.01)
            continue

        if not message:
            continue

        if waiting and not has_initialized:
            print("Message received from TERA Radar, Starting Game")
            # Intiial Game Setup (run once)
            interception.press("esc")
            time.sleep(0.1)
            zoom_out()
            time.sleep(0.1)
            print("Beginning Target Entity in 5 Seconds")
            print("4")
            time.sleep(1)
            print("3")
            time.sleep(1)
            print("2")
            time.sleep(1)
            print("1")
            time.sleep(1)
            print("0")
            time.sleep(1)
            has_initialized = True
        waiting = False

        # Starting Pitch is always 0
        CURRENT_PITCH = 0

        data = json.loads(message)
        player_information = data['player']

        def distance_to_entity(player_information, entity_information):
            player_x = player_information['position']['x']
            player_y = player_information['position']['y']
            player_z = player_information['position']['z']
            entity_x = entity_information['position']['x']
            entity_y = entity_information['position']['y']
            entity_z = entity_information['position']['z']
            distance = math.sqrt((player_x - entity_x)**2 + (player_y - entity_y)**2 + (player_z - entity_z)**2)
            return distance

        # Sort entities by distance for better readability
        entities_with_distance = []
        for entity in data['entities']:
            pos = entity['position']
            dx = pos['x'] - player_information['position']['x']
            dy = pos['y'] - player_information['position']['y']
            dz = pos['z'] - player_information['position']['z']
            distance_units = math.sqrt(dx * dx + dy * dy + dz * dz)
            entities_with_distance.append((entity, distance_units))

        # Sort by distance (closest first)
        entities_with_distance.sort(key=lambda x: x[1])

        if len(entities_with_distance) > 0:
            target_entity_information = entities_with_distance[0][0]
        else:
            target_entity_information = None
            print("No entities found")
            time.sleep(1)
            continue

        if not has_locked_target:
            interception_movement = target_entity(player_information, target_entity_information, CURRENT_PITCH)
            interception.move_relative(interception_movement, 0)
            interception.press("w")
            has_locked_target = True
            continue

        distance = distance_to_entity(player_information, target_entity_information)
        interception_movement_total = 0
        movement_per_step = -10

        # Ensure the driver is installed and the correct devices are registered.
        inputs.auto_capture_devices(keyboard=True, mouse=False, verbose=False)

        context = Interception()
        context.set_filter(context.is_keyboard, FilterKeyFlag.FILTER_KEY_DOWN)

        print("Beginning Pitch Calibration")

        try:
            print("Press Ctrl+C in this terminal to stop calibration.")
            while True:
                device = context.await_input()
                if device is None:
                    continue

                stroke = context.devices[device].receive()
                if stroke is None:
                    continue

                context.send(device, stroke)  # let the original input propagate

                interception_movement_total += movement_per_step
                interception.move_relative(0, movement_per_step)
        except KeyboardInterrupt:
            print("Pitch calibration interrupted by user; exiting.")
            should_exit = True
        finally:
            context.destroy()

        if should_exit:
            break

        print(f"At {distance} units, the interception movement is {interception_movement_total}")
        print(f"Player Height: {player_information['position']['z']}")
        print(f"Target Entity Height: {target_entity_information['position']['z']}")

    radar_socket.close()
