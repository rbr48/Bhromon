import os
import shutil
import subprocess
import sys
import zipfile

# 1. Self-install paramiko if not available
try:
    import paramiko
except ImportError:
    print("Paramiko not found. Installing...")
    subprocess.run([sys.executable, "-m", "pip", "install", "paramiko"])
    import paramiko

# ── VPS connection settings ────────────────────────────────────────────
# Authentication uses the SSH key at VPS_KEY_PATH (no password needed).
# Override any setting via environment variables if required.
# ─────────────────────────────────────────────────────────────
VPS_IP       = os.environ.get('VPS_IP', '148.135.137.245')
VPS_PORT     = int(os.environ.get('VPS_PORT', '2222'))
VPS_USER     = os.environ.get('VPS_USER', 'root')
VPS_KEY_PATH = os.environ.get('VPS_KEY_PATH', os.path.join(os.path.expanduser('~'), '.ssh', 'bhromon_vps'))
DEPLOY_DIR   = '/root/bhromon-deploy'

if not os.path.exists(VPS_KEY_PATH):
    print(f'ERROR: SSH private key not found at: {VPS_KEY_PATH}')
    print('Generate one with:')
    print('  ssh-keygen -t ed25519 -f ~/.ssh/bhromon_vps')
    print('Then install it on the VPS with:')
    print('  ssh-copy-id -i ~/.ssh/bhromon_vps.pub -p 2222 root@<VPS_IP>')
    sys.exit(1)

def build_flutter_web():
    print("Building Flutter Web locally...")
    # Run flutter build web
    result = subprocess.run("flutter build web", shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print("Flutter build failed:")
        print(result.stderr)
        sys.exit(1)
    print("Flutter build successful!")

def zip_directory(src_dir, zip_path):
    print(f"Zipping {src_dir} to {zip_path}...")
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
        for root, dirs, files in os.walk(src_dir):
            for file in files:
                file_path = os.path.join(root, file)
                # Ensure relative paths inside zip
                arcname = os.path.relpath(file_path, src_dir)
                zipf.write(file_path, arcname)
    print("Zip created successfully.")

def run_remote_commands(ssh, commands):
    for cmd in commands:
        print(f"Executing: {cmd}")
        stdin, stdout, stderr = ssh.exec_command(cmd)
        exit_status = stdout.channel.recv_exit_status()
        
        # Read streams
        out = stdout.read().decode('utf-8')
        err = stderr.read().decode('utf-8')
        
        if out.strip():
            print("STDOUT:")
            print(out)
        if err.strip():
            print("STDERR:")
            print(err)
            
        if exit_status != 0:
            print(f"Command failed with exit code: {exit_status}")
            sys.exit(1)

def deploy():
    # Paths
    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    build_web_dir = os.path.join(project_root, "build", "web")
    deploy_assets_dir = os.path.join(project_root, "deployment")
    zip_out = os.path.join(deploy_assets_dir, "web.zip")
    
    # Clean up previous local zip if exists
    if os.path.exists(zip_out):
        os.remove(zip_out)
        
    # Build and zip
    build_flutter_web()
    zip_directory(build_web_dir, zip_out)
    
    print('Connecting to VPS via SSH (key auth)...')
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    if os.path.exists(VPS_KEY_PATH):
        print(f"Connecting using SSH key: {VPS_KEY_PATH}")
        ssh.connect(VPS_IP, port=VPS_PORT, username=VPS_USER, key_filename=VPS_KEY_PATH, timeout=30)
    else:
        print("Connecting using password...")
        ssh.connect(VPS_IP, port=VPS_PORT, username=VPS_USER, password="WcT/VxM86?Dv)GzR", timeout=30)
    print('Connected successfully!')
        
        # Open SFTP client
        sftp = ssh.open_sftp()
        
        # Ensure remote deploy dir exists
        try:
            sftp.mkdir(DEPLOY_DIR)
        except IOError:
            pass # already exists
            
        print("Uploading deployment files...")
        # Upload files
        sftp.put(os.path.join(deploy_assets_dir, "web.zip"),               f"{DEPLOY_DIR}/web.zip")
        sftp.put(os.path.join(deploy_assets_dir, "Dockerfile"),             f"{DEPLOY_DIR}/Dockerfile")
        sftp.put(os.path.join(deploy_assets_dir, "nginx.conf"),             f"{DEPLOY_DIR}/nginx.conf")
        sftp.put(os.path.join(deploy_assets_dir, "host_nginx.conf"),        f"{DEPLOY_DIR}/host_nginx.conf")
        sftp.put(os.path.join(deploy_assets_dir, "bhromon-notif-daemon.service"), "/etc/systemd/system/bhromon-notif-daemon.service")
        
        sftp.close()
        print("Upload completed.")
        
        # Setup commands to run on VPS
        commands = [
            # 1. Update packages and install Docker + unzip if not present
            "apt-get update -y",
            "which unzip || apt-get install -y unzip",
            "which docker || apt-get install -y docker.io",
            # 2. Extract zip
            f"cd {DEPLOY_DIR} && rm -rf web && unzip -o web.zip -d web",
            # 3. Clean up previous docker containers if present
            "docker stop bhromon-app || true",
            "docker rm bhromon-app || true",
            "docker rmi bhromon-web || true",
            # 4. Build and run new docker container
            f"cd {DEPLOY_DIR} && docker build -t bhromon-web .",
            "docker run -d --name bhromon-app -p 127.0.0.1:8085:80 --restart always bhromon-web",
            # 5. Configure Host Nginx
            f"cp {DEPLOY_DIR}/host_nginx.conf /etc/nginx/sites-available/bhromon.bpep.info",
            "ln -sf /etc/nginx/sites-available/bhromon.bpep.info /etc/nginx/sites-enabled/bhromon.bpep.info",
            "nginx -t",
            "systemctl reload nginx",
            # 6. Configure SSL via Certbot (failsafe)
            "certbot --nginx -d bhromon.bpep.info --non-interactive --agree-tos --register-unsafely-without-email || echo 'Certbot failed, continuing with HTTP only'",
            # 7. Install Node.js (required by notif-daemon) if not present
            "which node || (curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && apt-get install -y nodejs)",
            # 8. Install notif-daemon dependencies
            f"cd {DEPLOY_DIR}/notif-daemon && npm ci --omit=dev || true",
            # 9. Register the daemon service unit (installed but DISABLED by default).
            #    Cloud Functions are the recommended primary delivery path.
            #    Enable manually with: systemctl enable --now bhromon-notif-daemon
            "systemctl daemon-reload",
            "systemctl is-active bhromon-notif-daemon && echo 'Daemon already running, restarting...' && systemctl restart bhromon-notif-daemon || echo 'Daemon not active (OK — Cloud Functions is the primary path)'",
            # 10. Check if web container is running
            "docker ps | grep bhromon-app"
        ]
        
        run_remote_commands(ssh, commands)
        print("\nDeployment completed successfully!")
        print("Verify your application at https://bhromon.bpep.info or http://bhromon.bpep.info")
        
    finally:
        ssh.close()

if __name__ == "__main__":
    deploy()
