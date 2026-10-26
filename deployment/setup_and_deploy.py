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

# Configurations
VPS_IP = os.environ.get('VPS_IP', '148.135.137.245')
VPS_PORT = int(os.environ.get('VPS_PORT', '2222'))
VPS_USER = os.environ.get('VPS_USER', 'root')
VPS_KEY_PATH = os.environ.get('VPS_KEY_PATH', os.path.join(os.path.expanduser('~'), '.ssh', 'bhromon_vps'))
VPS_PASS = os.environ.get('VPS_PASS', '')
DB_PASSWORD = os.environ.get('BHROMON_DB_PASSWORD', '')
if __name__ == "__main__" and not DB_PASSWORD:
    sys.exit('Set BHROMON_DB_PASSWORD to the password for the bhromon_user database role')
DEPLOY_DIR = "/root/bhromon-deploy"

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
        print(f"\nExecuting: {cmd}")
        stdin, stdout, stderr = ssh.exec_command(cmd)
        exit_status = stdout.channel.recv_exit_status()
        
        # Read streams
        out = stdout.read().decode('utf-8', errors='ignore')
        err = stderr.read().decode('utf-8', errors='ignore')
        
        if out.strip():
            print("STDOUT:")
            try:
                print(out)
            except UnicodeEncodeError:
                print(out.encode('ascii', errors='replace').decode('ascii'))
        if err.strip():
            print("STDERR:")
            try:
                print(err)
            except UnicodeEncodeError:
                print(err.encode('ascii', errors='replace').decode('ascii'))
            
        if exit_status != 0:
            print(f"Warning/Error: Command exited with code {exit_status}")

def deploy():
    # Paths
    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    build_web_dir = os.path.join(project_root, "build", "web")
    deploy_assets_dir = os.path.join(project_root, "deployment")
    zip_out = os.path.join(deploy_assets_dir, "web.zip")
    
    # Clean up previous local zip if exists
    if os.path.exists(zip_out):
        os.remove(zip_out)
        
    zip_out_website = os.path.join(deploy_assets_dir, "website.zip")
    if os.path.exists(zip_out_website):
        os.remove(zip_out_website)
        
    # Build and zip
    build_flutter_web()

    # Generate version.json dynamically
    pubspec_path = os.path.join(project_root, "pubspec.yaml")
    version_str = "1.0.0"
    build_num = "1"
    if os.path.exists(pubspec_path):
        with open(pubspec_path, "r", encoding="utf-8") as f:
            for line in f:
                if line.strip().startswith("version:"):
                    v_part = line.split("version:")[1].strip()
                    if "+" in v_part:
                        version_str, build_num = v_part.split("+")
                    else:
                        version_str = v_part
                    break
    
    import json
    version_json_path = os.path.join(build_web_dir, "version.json")
    with open(version_json_path, "w", encoding="utf-8") as f:
        json.dump({
            "app_name": "bhromon",
            "version": version_str,
            "build_number": build_num,
            "package_name": "bhromon"
        }, f)
    print(f"Generated version.json locally: version={version_str}, build={build_num}")
    
    # Copy Android APK to web/downloads directory so it is served by the Nginx container
    apk_paths = [
        os.path.join(project_root, "build", "app", "outputs", "flutter-apk", "app-release.apk"),
        os.path.join(project_root, "build", "app", "outputs", "flutter-apk", "app-debug.apk")
    ]
    apk_copied = False
    for apk_path in apk_paths:
        if os.path.exists(apk_path):
            downloads_dir = os.path.join(build_web_dir, "downloads")
            os.makedirs(downloads_dir, exist_ok=True)
            shutil.copy2(apk_path, os.path.join(downloads_dir, "bhromon-latest.apk"))
            print(f"Bundling Android APK to web/downloads/bhromon-latest.apk from {apk_path}")
            apk_copied = True
            break
            
    if not apk_copied:
        print("Warning: Android APK not found. Build Android first to host it.")
        
    zip_directory(build_web_dir, zip_out)
    
    # Zip landing page website
    website_src_dir = os.path.join(project_root, "Bhromon Website")
    zip_directory(website_src_dir, zip_out_website)
    
    print("Connecting to VPS via SSH...")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    
    try:
        if os.path.exists(VPS_KEY_PATH):
            print(f"Connecting using SSH key: {VPS_KEY_PATH}")
            ssh.connect(VPS_IP, port=VPS_PORT, username=VPS_USER, key_filename=VPS_KEY_PATH, timeout=30)
        else:
            if not VPS_PASS:
                sys.exit('No SSH key at VPS_KEY_PATH, and VPS_PASS is not set')
            print("Connecting using password...")
            ssh.connect(VPS_IP, port=VPS_PORT, username=VPS_USER, password=VPS_PASS, timeout=30)
        print("Connected successfully!")
        
        # Open SFTP client
        sftp = ssh.open_sftp()
        
        # Ensure remote deploy dir exists
        try:
            sftp.mkdir(DEPLOY_DIR)
        except IOError:
            pass # already exists
            
        print("Uploading deployment files...")
        # Upload files
        sftp.put(os.path.join(deploy_assets_dir, "web.zip"), f"{DEPLOY_DIR}/web.zip")
        sftp.put(os.path.join(deploy_assets_dir, "website.zip"), f"{DEPLOY_DIR}/website.zip")
        sftp.put(os.path.join(deploy_assets_dir, "Dockerfile"), f"{DEPLOY_DIR}/Dockerfile")
        sftp.put(os.path.join(deploy_assets_dir, "nginx.conf"), f"{DEPLOY_DIR}/nginx.conf")
        sftp.put(os.path.join(deploy_assets_dir, "host_nginx.conf"), f"{DEPLOY_DIR}/host_nginx.conf")
        sftp.put(os.path.join(deploy_assets_dir, "upload_server.py"), f"{DEPLOY_DIR}/upload_server.py")
        sftp.put(os.path.join(deploy_assets_dir, "bhromon-upload.service"), f"{DEPLOY_DIR}/bhromon-upload.service")
        sftp.put(os.path.join(deploy_assets_dir, "db_backup.sh"), f"{DEPLOY_DIR}/db_backup.sh")
        
        sftp.close()
        print("Upload completed.")
        
        # Setup commands to run on VPS
        commands = [
            # 1. Update packages and install tools + Nginx + Docker + unzip if not present
            "export DEBIAN_FRONTEND=noninteractive",
            "apt-get update -y",
            "which unzip || apt-get install -y unzip",
            "which docker || apt-get install -y docker.io",
            "which nginx || apt-get install -y nginx",
            "apt-get install -y python3-flask python3-pip || pip3 install flask || pip install flask",
            "which rclone || apt-get install -y rclone",
            
            # 2. Setup PostgreSQL
            "echo '=== Setting up PostgreSQL ==='",
            "which psql || apt-get install -y postgresql postgresql-contrib",
            "systemctl start postgresql",
            "systemctl enable postgresql",
            "sudo -u postgres psql -c \"CREATE DATABASE bhromon_db;\" || echo 'Postgres DB already exists or failed'",
            "sudo -u postgres psql -c \"CREATE USER bhromon_user WITH PASSWORD '" + DB_PASSWORD + "';\" || echo 'Postgres User already exists or failed'",
            "sudo -u postgres psql -c \"GRANT ALL PRIVILEGES ON DATABASE bhromon_db TO bhromon_user;\" || echo 'Grant failed'",
            
            # 3. Setup MySQL / MariaDB
            "echo '=== Setting up MySQL ==='",
            "which mysql || apt-get install -y mariadb-server || apt-get install -y mysql-server",
            "systemctl start mysql || systemctl start mariadb",
            "systemctl enable mysql || systemctl enable mariadb",
            "mysql -e \"CREATE DATABASE IF NOT EXISTS bhromon_db;\" || echo 'MySQL DB already exists or failed'",
            "mysql -e \"CREATE USER IF NOT EXISTS 'bhromon_user'@'localhost' IDENTIFIED BY '" + DB_PASSWORD + "';\" || echo 'MySQL User already exists or failed'",
            "mysql -e \"GRANT ALL PRIVILEGES ON bhromon_db.* TO 'bhromon_user'@'localhost';\" || echo 'Grant failed'",
            "mysql -e \"FLUSH PRIVILEGES;\" || echo 'Flush failed'",
            
            # 4. Extract web zip
            f"cd {DEPLOY_DIR} && rm -rf web && unzip -o web.zip -d web",
            
            # Extract landing page website
            "echo '=== Setting up Static Landing Page ==='",
            "mkdir -p /var/www/bhromon/website",
            f"cd {DEPLOY_DIR} && unzip -o website.zip -d /var/www/bhromon/website",
            "chown -R www-data:www-data /var/www/bhromon/website",
            "chmod -R 755 /var/www/bhromon/website",
            
            # 5. Clean up previous docker containers if present
            "docker stop bhromon-app || true",
            "docker rm bhromon-app || true",
            "docker rmi bhromon-web || true",
            
            # 6. Build and run new docker container
            f"cd {DEPLOY_DIR} && docker build -t bhromon-web .",
            "docker run -d --name bhromon-app -p 127.0.0.1:8085:80 --restart always bhromon-web",
            
            # 7. Configure Host Nginx
            f"cp {DEPLOY_DIR}/host_nginx.conf /etc/nginx/sites-available/bhromon.bpep.info",
            "ln -sf /etc/nginx/sites-available/bhromon.bpep.info /etc/nginx/sites-enabled/bhromon.bpep.info",
            "nginx -t",
            "systemctl reload nginx",

            # 8. Setup Bhromon Upload Service
            "echo '=== Setting up Bhromon Upload Service ==='",
            "mkdir -p /var/www/bhromon/uploads",
            "chmod 775 /var/www/bhromon/uploads",
            "chown -R root:www-data /var/www/bhromon/uploads",
            f"cp {DEPLOY_DIR}/bhromon-upload.service /etc/systemd/system/bhromon-upload.service",
            "systemctl daemon-reload",
            "systemctl enable bhromon-upload",
            "systemctl restart bhromon-upload",
            "systemctl status bhromon-upload --no-pager | grep -i active",
            
            "echo '=== Skipping Certbot step as SSL is already configured in host_nginx.conf ==='",
            
            # 10. Setup Database Backup Script
            "echo '=== Setting up Database Backup Script ==='",
            "chmod +x /root/bhromon-deploy/db_backup.sh",
            "(crontab -l 2>/dev/null | grep -F '/root/bhromon-deploy/db_backup.sh') || (crontab -l 2>/dev/null; echo '0 2 * * * /root/bhromon-deploy/db_backup.sh >/dev/null 2>&1') | crontab -",
            
            # 11. Check if running
            "docker ps | grep bhromon-app",
            "systemctl status postgresql --no-pager | grep -i active",
            "systemctl status mysql --no-pager | grep -i active || systemctl status mariadb --no-pager | grep -i active"
        ]
        
        run_remote_commands(ssh, commands)
        print("\nDeployment and Database Setup completed successfully!")
        print("Verify your application at https://app.bhromon.fun or https://bhromon.fun")
        
    finally:
        ssh.close()

if __name__ == "__main__":
    deploy()
