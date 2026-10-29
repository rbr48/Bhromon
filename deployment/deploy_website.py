"""
deploy_website.py — Deploy Bhromon Website (static landing page) to the VPS.
Uses paramiko so there are no PowerShell shell-escaping issues.
"""

import os
import sys
import zipfile

try:
    import paramiko
except ImportError:
    import subprocess
    subprocess.run([sys.executable, "-m", "pip", "install", "paramiko"], check=True)
    import paramiko

# ── VPS settings ──────────────────────────────────────────────────────────────
VPS_IP       = os.environ.get("VPS_IP",       "148.135.137.245")
VPS_PORT     = int(os.environ.get("VPS_PORT", "2222"))
VPS_USER     = os.environ.get("VPS_USER",     "root")
VPS_KEY_PATH = os.environ.get(
    "VPS_KEY_PATH",
    os.path.join(os.path.expanduser("~"), ".ssh", "bhromon_vps"),
)

DEPLOY_DIR   = "/root/bhromon-website-deploy"
WEBSITE_ROOT = "/var/www/bhromon/website"

# Local paths
SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
WEBSITE_SRC  = os.path.join(PROJECT_ROOT, "Bhromon Website")
ZIP_OUT      = os.path.join(SCRIPT_DIR,   "website.zip")
APK_SRC          = os.path.join(WEBSITE_SRC,  "app-release.apk")
ARM64_APK_SRC    = os.path.join(PROJECT_ROOT, "build", "app", "outputs", "flutter-apk", "app-arm64-v8a-release.apk")
UNIVERSAL_APK_SRC = os.path.join(PROJECT_ROOT, "build", "app", "outputs", "flutter-apk", "app-release.apk")
AAB_SRC          = os.path.join(PROJECT_ROOT, "build", "app", "outputs", "bundle", "release", "app-release.aab")
SYMBOLS_SRC      = os.path.join(PROJECT_ROOT, "build", "app", "outputs", "symbols.zip")

# ── helpers ───────────────────────────────────────────────────────────────────

def run(ssh: paramiko.SSHClient, cmd: str, allow_fail: bool = False) -> str:
    print(f"  $ {cmd}")
    _, stdout, stderr = ssh.exec_command(cmd)
    exit_code = stdout.channel.recv_exit_status()
    out = stdout.read().decode().strip()
    err = stderr.read().decode().strip()
    if out:
        print(f"    {out}")
    if err:
        print(f"    STDERR: {err}")
    if exit_code != 0 and not allow_fail:
        print(f"  Command failed (exit {exit_code})")
        sys.exit(1)
    return out


def build_zip():
    EXCLUDE = {"app-release.apk"}
    print(f"\n[1/5] Building website.zip from: {WEBSITE_SRC}")
    if os.path.exists(ZIP_OUT):
        os.remove(ZIP_OUT)
    with zipfile.ZipFile(ZIP_OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for root, dirs, files in os.walk(WEBSITE_SRC):
            for f in files:
                if f in EXCLUDE:
                    print(f"  Skipping: {f}")
                    continue
                fp  = os.path.join(root, f)
                arc = os.path.relpath(fp, WEBSITE_SRC)
                zf.write(fp, arc)
                print(f"  + {arc}")
    size_kb = os.path.getsize(ZIP_OUT) / 1024
    print(f"  website.zip -> {size_kb:.0f} KB")


def connect() -> paramiko.SSHClient:
    print(f"\n[2/5] Connecting to {VPS_USER}@{VPS_IP}:{VPS_PORT} ...")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    key_candidates = [
        VPS_KEY_PATH,
        os.path.join(os.path.expanduser("~"), ".ssh", "id_rsa_dbm"),
        os.path.join(os.path.expanduser("~"), ".ssh", "bhromon_vps"),
    ]
    connected = False
    for k in key_candidates:
        if os.path.exists(k):
            try:
                print(f"  Trying SSH key: {k}")
                ssh.connect(VPS_IP, port=VPS_PORT, username=VPS_USER,
                            key_filename=k, timeout=20)
                connected = True
                print(f"  Connected using {k}!")
                break
            except Exception as e:
                print(f"  Key {k} failed: {e}")
    if not connected:
        if not os.environ.get('VPS_PASS'):
            sys.exit('No working SSH key found and VPS_PASS is not set')
        print("  Connecting using password fallback...")
        ssh.connect(VPS_IP, port=VPS_PORT, username=VPS_USER,
                    password=os.environ.get("VPS_PASS", ""), timeout=30)
        print("  Connected!")
    return ssh


def send_file(ssh: paramiko.SSHClient, local_path: str, remote_path: str):
    """Transfers file via SFTP or falls back to SSH stdin stream if SFTP subsystem is unavailable."""
    try:
        sftp = ssh.open_sftp()
        sftp.put(local_path, remote_path)
        sftp.close()
        return
    except Exception as sftp_err:
        print(f"    (SFTP unavailable: {sftp_err}; using SSH pipe transfer)")

    # Fallback to stdin pipe
    cmd = f"cat > '{remote_path}'"
    stdin, stdout, stderr = ssh.exec_command(cmd)
    with open(local_path, "rb") as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            stdin.write(chunk)
    stdin.flush()
    stdin.channel.shutdown_write()
    exit_status = stdout.channel.recv_exit_status()
    if exit_status != 0:
        err = stderr.read().decode()
        raise RuntimeError(f"Failed to stream {local_path} to {remote_path}: {err}")


def upload(ssh: paramiko.SSHClient):
    print(f"\n[3/5] Uploading files ...")
    # Ensure deploy dir
    run(ssh, f"mkdir -p '{DEPLOY_DIR}'")

    send_file(ssh, ZIP_OUT, f"{DEPLOY_DIR}/website.zip")
    print(f"  [OK] website.zip uploaded")

    # Upload APK separately to downloads
    downloads_dir = "/var/www/bhromon/downloads"
    run(ssh, f"mkdir -p '{downloads_dir}'")

    # Upload Split ARM64 APK
    if os.path.exists(ARM64_APK_SRC):
        arm64_mb = os.path.getsize(ARM64_APK_SRC) / (1024 * 1024)
        print(f"  Uploading app-arm64-v8a-release.apk ({arm64_mb:.1f} MB) ...")
        send_file(ssh, ARM64_APK_SRC, f"{downloads_dir}/app-arm64-v8a-release.apk")
        print(f"  [OK] app-arm64-v8a-release.apk uploaded to {downloads_dir}/")

    # Upload Universal APK
    src_to_use = UNIVERSAL_APK_SRC if os.path.exists(UNIVERSAL_APK_SRC) else APK_SRC
    if os.path.exists(src_to_use):
        apk_size_mb = os.path.getsize(src_to_use) / (1024 * 1024)
        print(f"  Uploading app-release.apk ({apk_size_mb:.1f} MB) ... this may take a moment")
        send_file(ssh, src_to_use, f"{downloads_dir}/app-release.apk")
        print(f"  [OK] app-release.apk uploaded to {downloads_dir}/")
    else:
        print(f"  (Skipping Universal APK - not found)")

    # Upload AAB separately to downloads
    if os.path.exists(AAB_SRC):
        aab_size_mb = os.path.getsize(AAB_SRC) / (1024 * 1024)
        print(f"  Uploading app-release.aab ({aab_size_mb:.1f} MB) ... this may take a moment")
        send_file(ssh, AAB_SRC, f"{downloads_dir}/app-release.aab")
        print(f"  [OK] app-release.aab uploaded to {downloads_dir}/")
    else:
        print(f"  (Skipping AAB - not found at {AAB_SRC})")

    # Upload symbols ZIP separately to downloads
    if os.path.exists(SYMBOLS_SRC):
        symbols_size_mb = os.path.getsize(SYMBOLS_SRC) / (1024 * 1024)
        print(f"  Uploading symbols.zip ({symbols_size_mb:.1f} MB) ...")
        send_file(ssh, SYMBOLS_SRC, f"{downloads_dir}/symbols.zip")
        print(f"  [OK] symbols.zip uploaded to {downloads_dir}/")
    else:
        print(f"  (Skipping symbols.zip - not found at {SYMBOLS_SRC})")


def deploy_remote(ssh: paramiko.SSHClient):
    print(f"\n[4/5] Deploying on VPS ...")

    commands = [
        # Ensure website dir exists
        f"mkdir -p {WEBSITE_ROOT}",
        # Clear old content (safe: only inside website dir)
        f"find {WEBSITE_ROOT} -mindepth 1 -delete",
        # Ensure unzip is available
        "which unzip || apt-get install -y unzip",
        # Extract zip
        f"unzip -o {DEPLOY_DIR}/website.zip -d {WEBSITE_ROOT}",
        # Permissions
        f"find {WEBSITE_ROOT} -type f -exec chmod 644 {{}} \\;",
        f"find {WEBSITE_ROOT} -type d -exec chmod 755 {{}} \\;",
        f"chown -R www-data:www-data {WEBSITE_ROOT} 2>/dev/null || true",
        # Downloads dir permissions and dual-location sync
        "chown -R www-data:www-data /var/www/bhromon/downloads 2>/dev/null || true",
        "find /var/www/bhromon/downloads -type f -exec chmod 644 {} \\; 2>/dev/null || true",
        "cd /var/www/bhromon/downloads && ln -sfn app-release.apk bhromon-release.apk 2>/dev/null || true",
        "mkdir -p /var/www/bhromon-media/apk 2>/dev/null || true",
        "ln -sfn /var/www/bhromon/downloads/app-release.apk /var/www/bhromon-media/apk/bhromon-release.apk 2>/dev/null || true",
        "ln -sfn /var/www/bhromon/downloads/app-release.apk /var/www/bhromon-media/apk/app-release.apk 2>/dev/null || true",
        "ln -sfn /var/www/bhromon/downloads /var/www/bhromon/website/downloads 2>/dev/null || true",
        # Test and reload nginx
        "nginx -t",
        "systemctl reload nginx",
        # List deployed files
        f"ls -lh {WEBSITE_ROOT}/",
    ]

    for cmd in commands:
        run(ssh, cmd, allow_fail=("chown" in cmd or "downloads" in cmd))


def verify(ssh: paramiko.SSHClient):
    print(f"\n[5/5] Verifying ...")
    result = run(ssh, f"ls -lh {WEBSITE_ROOT}/", allow_fail=True)
    print("\nDeployment complete!")
    print("   -> https://bhromon.fun")
    print("   -> https://www.bhromon.fun")


def main():
    build_zip()
    ssh = connect()
    try:
        upload(ssh)
        deploy_remote(ssh)
        verify(ssh)
    finally:
        ssh.close()
        print("\nSSH connection closed.")


if __name__ == "__main__":
    main()
