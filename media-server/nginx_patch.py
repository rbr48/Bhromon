#!/usr/bin/env python3
import sys

NGINX_CONF = "/etc/nginx/sites-available/bhromon.fun"

TARGET = "    # Bhromon VPS Quiz Engine: API proxy to Docker container"
NEWS_BLOCK = """    # Bhromon VPS Newspaper Hub: API proxy to Docker container
    location /api/news/ {
        proxy_pass             http://127.0.0.1:8210/api/news/;
        proxy_http_version     1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection        "";

        proxy_read_timeout         60s;
        proxy_send_timeout         60s;
    }

"""

try:
    with open(NGINX_CONF, "r") as f:
        content = f.read()

    if "/api/news/" in content:
        print("Newspaper Hub proxy block is already present in nginx config.")
        sys.exit(0)

    if TARGET not in content:
        print(f"Target '{TARGET}' not found in {NGINX_CONF}")
        sys.exit(1)

    new_content = content.replace(TARGET, NEWS_BLOCK + TARGET)
    with open(NGINX_CONF, "w") as f:
        f.write(new_content)

    print("Successfully added Newspaper Hub proxy block to nginx config.")
except Exception as e:
    print(f"Error updating nginx config: {e}")
    sys.exit(1)
