import requests
import time
import json
import os
import sys


class TeraBridge:
    def __init__(self, host="127.0.0.1", port=8081):
        self.base_url = f"http://{host}:{port}"

    def get_game_data(self):
        """Get current game state"""
        try:
            response = requests.get(f"{self.base_url}/game-data")
            response.raise_for_status()
            return response.json()
        except requests.RequestException as e:
            print(f"Error getting game data: {e}")
            return None

    def send_action(self, action):
        """Send action to game"""
        try:
            response = requests.post(
                f"{self.base_url}/action",
                json=action,
                headers={"Content-Type": "application/json"}
            )
            response.raise_for_status()
            return response.json()
        except requests.RequestException as e:
            print(f"Error sending action: {e}")
            return None
    
    def get_status(self):
        """Get server status"""
        try:
            response = requests.get(f"{self.base_url}/status")
            response.raise_for_status()
            return response.json()
        except requests.RequestException as e:
            print(f"Error getting status: {e}")
            return None


def clear_screen():
    """Clear the terminal screen"""
    os.system('cls' if os.name == 'nt' else 'clear')


def format_position(pos):
    """Format position data nicely"""
    if pos:
        return f"({pos.get('x', 0):.1f}, {pos.get('y', 0):.1f}, {pos.get('z', 0):.1f})"
    return "None"


def display_game_data(game_data):
    """Display game data in a formatted way"""
    clear_screen()
    
    print("=" * 60)
    print("                    TERA GAME DATA MONITOR")
    print("=" * 60)
    print(f"Last Update: {time.strftime('%H:%M:%S')}")
    print()
    
    if not game_data:
        print("No game data available")
        return
    
    # Debug: Print raw player data to see what we're getting
    if game_data.get('player'):
        print("DEBUG - Raw player data:")
        print(f"  Position: {game_data['player'].get('position')}")
        print(f"  Direction: {game_data['player'].get('direction')}")
        print()
    
    # Player Information
    print("PLAYER INFORMATION")
    print("-" * 30)
    if game_data.get('player'):
        player = game_data['player']
        print(f"Name: {player.get('name', 'Unknown')}")
        print(f"Class: {player.get('class', 'Unknown')}")
        print(f"Level: {player.get('level', 0)}")
        print(f"HP: {player.get('hp', 0)}/{player.get('maxHp', 0)}")
        print(f"Alive: {'YES' if player.get('alive', False) else 'NO'}")
        print(f"Position: {format_position(player.get('position'))}")
        print(f"Direction: {player.get('direction', 0):.2f}")
        print(f"ID: {player.get('id', 0)}")
        print(f"Template ID: {player.get('templateId', 0)}")
    else:
        print("No player data (not logged in or character not spawned)")
    
    print()
    
    # Zone Information
    print("ZONE INFORMATION")
    print("-" * 30)
    zone = game_data.get('zone', 'Unknown')
    print(f"Current Zone: {zone}")
    
    print()
    
    # Enemy Information
    print("ENEMY INFORMATION")
    print("-" * 30)
    enemies = game_data.get('enemies', [])
    print(f"Total Enemies: {len(enemies)}")
    
    if enemies:
        print("\nNearby Enemies:")
        for i, enemy in enumerate(enemies[:5], 1):  # Show first 5 enemies
            hp_percent = (enemy.get('hp', 0) / enemy.get('maxHp', 1)) * 100 if enemy.get('maxHp', 0) > 0 else 0
            print(f"  {i}. {enemy.get('name', 'Unknown')}")
            print(f"     HP: {enemy.get('hp', 0)}/{enemy.get('maxHp', 0)} ({hp_percent:.1f}%)")
            print(f"     Position: {format_position(enemy.get('position'))}")
            print(f"     ID: {enemy.get('id', 0)}")
            print()
        
        if len(enemies) > 5:
            print(f"  ... and {len(enemies) - 5} more enemies")
    else:
        print("No enemies detected")
    
    print()
    
    # System Information
    print("SYSTEM INFORMATION")
    print("-" * 30)
    print(f"Timestamp: {game_data.get('timestamp', 0)}")
    print(f"Data Age: {time.time() - (game_data.get('timestamp', 0) / 1000):.1f}s ago")
    
    print()
    print("=" * 60)
    print("Press Ctrl+C to stop monitoring")


def monitor_game_data():
    """Continuously monitor and display game data"""
    bridge = TeraBridge()
    
    print("Starting TERA Game Data Monitor...")
    print("Connecting to Python Bridge...")
    
    last_position = None
    last_direction = None
    
    try:
        while True:
            game_data = bridge.get_game_data()
            
            # Check if position/direction changed
            if game_data and game_data.get('player'):
                current_position = game_data['player'].get('position')
                current_direction = game_data['player'].get('direction')
                
                if current_position != last_position:
                    print(f"POSITION CHANGED: {last_position} -> {current_position}")
                    last_position = current_position
                
                if current_direction != last_direction:
                    print(f"DIRECTION CHANGED: {last_direction} -> {current_direction}")
                    last_direction = current_direction
            
            display_game_data(game_data)
            time.sleep(1)  # Update every second
            
    except KeyboardInterrupt:
        print("\n\nMonitoring stopped by user")
        print("Goodbye!")
    except Exception as e:
        print(f"\nError: {e}")


if __name__ == "__main__":
    monitor_game_data()
