import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "deployment"))
from deploy_website import connect, run, send_file

def main():
    script_path = os.path.join(os.path.dirname(__file__), "delete_game_tables.js")
    ssh = connect()
    try:
        print("Uploading delete_game_tables.js to VPS...")
        send_file(ssh, script_path, "/tmp/delete_game_tables.js")
        run(ssh, "docker cp /tmp/delete_game_tables.js bhromon-games-app:/app/delete_game_tables.js")
        print("Executing delete_game_tables.js in bhromon-games-app...")
        run(ssh, "docker exec bhromon-games-app node /app/delete_game_tables.js")
        run(ssh, "docker exec bhromon-games-app rm -f /app/delete_game_tables.js")
        run(ssh, "rm -f /tmp/delete_game_tables.js")
    finally:
        ssh.close()

if __name__ == "__main__":
    main()
