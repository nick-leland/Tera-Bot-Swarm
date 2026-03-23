import zmq
import json
import time
import math
import os

TERA_UNITS_PER_METER = 16.49  # same factor the mod uses

socket = zmq.Context().socket(zmq.SUB)
socket.connect("tcp://127.0.0.1:3000")
socket.setsockopt(zmq.SUBSCRIBE, b"")


def clear_screen():
    os.system('cls' if os.name == 'nt' else 'clear')


def format_position(pos):
    return f"({pos['x']:8.1f}, {pos['y']:8.1f}, {pos['z']:8.1f})"


while True:
    try:
        message = socket.recv_string(zmq.NOBLOCK)
    except zmq.error.Again:
        time.sleep(0.01)
        continue

    if not message:
        continue

    data = json.loads(message)
    player_pos = data['player']['position']

    # Clear screen and show header
    clear_screen()
    print("=" * 80)
    print("TERA BOT - Entity Monitor")
    print("=" * 80)
    print(f"Player Position: {format_position(player_pos)}")
    print("-" * 80)
    print(f"{'Name':<20} {'Type':<15} {'Distance':<10} {'Position'}")
    print("-" * 80)

    # Sort entities by distance for better readability
    entities_with_distance = []
    for entity in data['entities']:
        pos = entity['position']
        dx = pos['x'] - player_pos['x']
        dy = pos['y'] - player_pos['y']
        dz = pos['z'] - player_pos['z']
        distance_units = math.sqrt(dx*dx + dy*dy + dz*dz)
        distance_m = distance_units / TERA_UNITS_PER_METER
        entities_with_distance.append((entity, distance_m))

    # Sort by distance (closest first)
    entities_with_distance.sort(key=lambda x: x[1])

    # Limit to 35 closest entities
    entities_to_show = entities_with_distance[:35]

    # Display entities
    for entity, distance_m in entities_to_show:
        name = entity['name'][:19]  # Truncate long names
        entity_type = entity['type'][:14]  # Truncate long types
        pos = entity['position']
        print(f"{name:<20} {entity_type:<15} {distance_m:>7.1f}m   {format_position(pos)}")

    print("=" * 80)
    print(f"Total entities: {len(data['entities'])}")
    print("Press Ctrl+C to exit")
