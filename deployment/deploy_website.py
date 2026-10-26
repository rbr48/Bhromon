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
APK_SRC      = os.path.join(WEBSITE_SRC,  "app-release.apk")
AAB_SRC      = os.path.join(PROJECT_ROOT, "build", "app", "outputs", "bundle", "release", "app-release.aab")
SYMBOLS_SRC  = os.path.join(PROJECT_ROOT, "build", "app", "outputs", "symbols.zip")

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
    if os.path.exists(VPS_KEY_PATH):
        print(f"  Connecting using SSH key: {VPS_KEY_PATH}")
        ssh.connect(VPS_IP, port=VPS_PORT, username=VPS_USER,
                    key_filename=VPS_KEY_PATH, timeout=30)
    else:
        if not os.environ.get('VPS_PASS'):
            sys.exit('No SSH key at VPS_KEY_PATH, and VPS_PASS is not set')
        print("  SSH key not found. Connecting using password fallback...")
        ssh.connect(VPS_IP, port=VPS_PORT, username=VPS_USER,
                    password=os.environ.get("VPS_PASS", ""), timeout=30)
    print("  Connected!")
    return ssh


def upload(ssh: paramiko.SSHClient):
    print(f"\n[3/5] Uploading files ...")
    sftp = ssh.open_sftp()
    # Ensure deploy dir
    try:
        sftp.mkdir(DEPLOY_DIR)
    except IOError:
        pass

    sftp.put(ZIP_OUT, f"{DEPLOY_DIR}/website.zip")
    print(f"  [OK] website.zip uploaded")

    # Upload APK separately to downloads
    downloads_dir = "/var/www/bhromon/downloads"
    try:
        sftp.mkdir(downloads_dir)
    except IOError:
        pass

    if os.path.exists(APK_SRC):
        apk_size_mb = os.path.getsize(APK_SRC) / (1024 * 1024)
        print(f"  Uploading app-release.apk ({apk_size_mb:.1f} MB) ... this may take a moment")
        sftp.put(APK_SRC, f"{downloads_dir}/app-release.apk")
        print(f"  [OK] app-release.apk uploaded to {downloads_dir}/")
    else:
        print(f"  (Skipping APK - not found at {APK_SRC})")

    # Upload AAB separately to downloads
    if os.path.exists(AAB_SRC):
        aab_size_mb = os.path.getsize(AAB_SRC) / (1024 * 1024)
        print(f"  Uploading app-release.aab ({aab_size_mb:.1f} MB) ... this may take a moment")
        sftp.put(AAB_SRC, f"{downloads_dir}/app-release.aab")
        print(f"  [OK] app-release.aab uploaded to {downloads_dir}/")
    else:
        print(f"  (Skipping AAB - not found at {AAB_SRC})")

    # Upload symbols ZIP separately to downloads
    if os.path.exists(SYMBOLS_SRC):
        symbols_size_mb = os.path.getsize(SYMBOLS_SRC) / (1024 * 1024)
        print(f"  Uploading symbols.zip ({symbols_size_mb:.1f} MB) ...")
        sftp.put(SYMBOLS_SRC, f"{downloads_dir}/symbols.zip")
        print(f"  [OK] symbols.zip uploaded to {downloads_dir}/")
    else:
        print(f"  (Skipping symbols.zip - not found at {SYMBOLS_SRC})")

    sftp.close()


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
        # Downloads dir permissions
        "chown -R www-data:www-data /var/www/bhromon/downloads 2>/dev/null || true",
        "find /var/www/bhromon/downloads -type f -exec chmod 644 {} \\; 2>/dev/null || true",
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
