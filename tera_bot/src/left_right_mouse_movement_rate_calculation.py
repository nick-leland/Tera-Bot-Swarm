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


def recv_latest_state(radar_socket):
    """Retrieve the most recent state available from the radar socket."""
    latest_message = None

    while True:
        try:
            latest_message = radar_socket.recv_string(zmq.NOBLOCK)
        except zmq.Again:
            break

    if latest_message is None:
        while True:
            try:
                latest_message = radar_socket.recv_string()
                break
            except zmq.error.Again:
                time.sleep(0.01)
        if latest_message is None:
            return None

    try:
        return json.loads(latest_message)
    except json.JSONDecodeError as exc:
        print(f"Failed to decode radar message: {exc}")
        return None


def select_closest_entity(player_information, entities):
    if not entities:
        return None, None

    player_pos = player_information['position']
    px, py, pz = player_pos['x'], player_pos['y'], player_pos['z']

    closest_entity = None
    closest_distance = float("inf")

    for entity in entities:
        pos = entity.get('position', {})
        dx = pos.get('x', 0) - px
        dy = pos.get('y', 0) - py
        dz = pos.get('z', 0) - pz
        distance_units = math.sqrt(dx * dx + dy * dy + dz * dz)

        if distance_units < closest_distance:
            closest_distance = distance_units
            closest_entity = entity

    return closest_entity, closest_distance


def refresh_player_and_target(radar_socket):
    state = recv_latest_state(radar_socket)
    if state is None:
        return None, None, None

    player_information = state.get('player')
    if player_information is None:
        return None, None, None

    entities = state.get('entities', [])
    target_entity_information, distance = select_closest_entity(player_information, entities)

    return player_information, target_entity_information, distance


def move_key_down(key: str, duration: float = 1.5):
    interception.key_down(key)
    time.sleep(duration)
    interception.key_up(key)


def move_and_refresh(radar_socket, key: str, duration: float, allow_missing_target: bool = False):
    move_key_down(key, duration)

    player_information, target_entity_information, distance = refresh_player_and_target(radar_socket)
    if player_information is None:
        print(f"Failed to receive player information after moving with key '{key}'.")
        return None, None, None

    if target_entity_information is None and not allow_missing_target:
        print("No target entity available after movement.")
        return player_information, None, distance

    if distance is not None and target_entity_information is not None:
        print(f"Distance to Entity: {distance}")

    return player_information, target_entity_information, distance


def strafe_entity_and_target(radar_socket, direction: str, current_pitch, duration: float = 1.5):
    player_information, target_entity_information, distance = move_and_refresh(
        radar_socket, direction, duration
    )

    if player_information is None or target_entity_information is None:
        return player_information, target_entity_information

    interception_movement = target_entity(player_information, target_entity_information, current_pitch)
    if distance is not None:
        print(f"Interception Movement: {interception_movement} at {distance} units")
    else:
        print(f"Interception Movement: {interception_movement}")
    interception.move_relative(interception_movement, 0)
    interception.press("s")
    interception.press("w")

    return player_information, target_entity_information


def run_left_right_calibration_sequence(radar_socket, player_information, target_entity_information, current_pitch, iteration_counts: int = 5):
    player_state = player_information
    target_state = target_entity_information

    print("Starting Left Movement")
    for _ in range(iteration_counts):
        for _ in range(iteration_counts):
            player_state, target_state = strafe_entity_and_target(radar_socket, "a", current_pitch)
            if player_state is None:
                print("Player information unavailable, aborting calibration.")
                return False
            if target_state is None:
                print("Target entity unavailable during left strafe, aborting calibration.")
                return False
            time.sleep(1)

        print("Moving Forward for 0.5 seconds")
        player_state, target_state, _ = move_and_refresh(radar_socket, "w", 0.5, allow_missing_target=True)
        if player_state is None:
            print("Player information unavailable after moving forward, aborting calibration.")
            return False
        time.sleep(1)

    print("Reset Position")
    player_state, target_state, _ = move_and_refresh(
        radar_socket, "s", iteration_counts * 0.5, allow_missing_target=True
    )
    if player_state is None:
        print("Player information unavailable during reset, aborting calibration.")
        return False

    print("Starting Right Movement")
    for _ in range(iteration_counts):
        for _ in range(iteration_counts):
            player_state, target_state = strafe_entity_and_target(radar_socket, "d", current_pitch)
            if player_state is None:
                print("Player information unavailable, aborting calibration.")
                return False
            if target_state is None:
                print("Target entity unavailable during right strafe, aborting calibration.")
                return False
            time.sleep(1)

        print("Moving Forward for 0.5 seconds")
        player_state, target_state, _ = move_and_refresh(radar_socket, "w", 0.5, allow_missing_target=True)
        if player_state is None:
            print("Player information unavailable after moving forward, aborting calibration.")
            return False
        time.sleep(1)

    print("Conclusion of Left and Right Movement")
    return True


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
    calibration_completed = False

    while True:
        try:
            # Blocking receive with timeout (RCVTIMEO). With CONFLATE, this is always the latest state.
            message = radar_socket.recv_string()
        except zmq.error.Again:
            if not waiting:
                print("No message received from TERA Radar, Waiting for message")
                waiting = True
            time.sleep(0.01)
            continue

        if message:
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
                interception.press("s")
                interception.press("w")
                print(
                    f"Target Entity Information | X: {target_entity_information['position']['x']}, "
                    f"Y: {target_entity_information['position']['y']}, Z: {target_entity_information['position']['z']}"
                )
                print(
                    f"Player Information | X: {player_information['position']['x']}, "
                    f"Y: {player_information['position']['y']}, Z: {player_information['position']['z']}, "
                    f"Rotation: {player_information['rotation']}"
                )
                has_locked_target = True
                continue

            if not calibration_completed:
                calibration_successful = run_left_right_calibration_sequence(
                    radar_socket,
                    player_information,
                    target_entity_information,
                    CURRENT_PITCH,
                )
                calibration_completed = True
                if not calibration_successful:
                    print("Calibration routine ended unsuccessfully.")
                break

        if not message:
            continue
