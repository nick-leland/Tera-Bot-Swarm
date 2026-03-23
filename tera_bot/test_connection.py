import requests
import sys


def test_bridge_connection():
    """Test if the Python Bridge server is running"""
    try:
        # Test the status endpoint first (lightweight)
        response = requests.get("http://127.0.0.1:8080/status", timeout=5)
        if response.status_code == 200:
            status = response.json()
            print("✅ Python Bridge is running!")
            print(f"   Status: {status.get('status', 'unknown')}")
            print(f"   Player Count: {status.get('playerCount', 0)}")
            print(f"   Enemy Count: {status.get('enemyCount', 0)}")
            print(f"   Zone: {status.get('zone', 'unknown')}")
            return True
        else:
            print(f"❌ Server responded with status code: {response.status_code}")
            return False
            
    except requests.exceptions.ConnectionError:
        print("❌ Connection failed! Python Bridge server is not running.")
        print("\nTo fix this:")
        print("1. Make sure Tera Proxy is running")
        print("2. Enable the 'Python Bridge' module in Tera Proxy settings")
        print("3. Check that the module loaded successfully")
        print("4. Verify the HTTP port (default: 8080) is not blocked")
        return False
        
    except requests.exceptions.Timeout:
        print("❌ Connection timed out! Server might be overloaded.")
        return False
        
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False

def test_game_data():
    """Test if we can get game data"""
    try:
        response = requests.get("http://127.0.0.1:8080/game-data", timeout=5)
        if response.status_code == 200:
            game_data = response.json()
            print("\n✅ Game data retrieved successfully!")
            
            if game_data.get('player'):
                player = game_data['player']
                print(f"   Player: {player.get('name', 'Unknown')} ({player.get('class', 'Unknown')})")
                print(f"   HP: {player.get('hp', 0)}/{player.get('maxHp', 0)}")
                print(f"   Level: {player.get('level', 0)}")
            else:
                print("   ⚠️  No player data (not logged in or character not spawned)")
            
            print(f"   Enemies: {len(game_data.get('enemies', []))}")
            print(f"   Zone: {game_data.get('zone', 'Unknown')}")
            return True
        else:
            print(f"❌ Failed to get game data: {response.status_code}")
            return False
            
    except Exception as e:
        print(f"❌ Error getting game data: {e}")
        return False

if __name__ == "__main__":
    print("Testing Python Bridge connection...")
    print("=" * 40)
    
    if test_bridge_connection():
        test_game_data()
    else:
        sys.exit(1) 