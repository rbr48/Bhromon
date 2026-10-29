#!/bin/bash

# Configuration
BACKUP_DIR="/root/bhromon-backups"
GDRIVE_REMOTE="gdrive:Bhromon_Backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Create local backup dir if not exists
mkdir -p "$BACKUP_DIR"

# 1. Backup PostgreSQL Database (if password set or socket available)
PG_FILE="$BACKUP_DIR/postgres_bhromon_${TIMESTAMP}.sql"
echo "[$(date)] Starting PostgreSQL backup..."
if [ -n "$BHROMON_DB_PASSWORD" ]; then
    PGPASSWORD="$BHROMON_DB_PASSWORD" pg_dump -h localhost -U bhromon_user -d bhromon_db -F p -f "$PG_FILE" 2>/dev/null
elif pg_isready -q 2>/dev/null; then
    pg_dump -U postgres -d bhromon_db -F p -f "$PG_FILE" 2>/dev/null
fi
if [ -s "$PG_FILE" ]; then
    gzip -f "$PG_FILE"
    echo "PostgreSQL backup completed: ${PG_FILE}.gz"
else
    rm -f "$PG_FILE"
fi

# 2. Backup MySQL Database
MY_FILE="$BACKUP_DIR/mysql_bhromon_${TIMESTAMP}.sql"
echo "[$(date)] Starting MySQL backup..."
if [ -n "$BHROMON_DB_PASSWORD" ]; then
    mysqldump --no-tablespaces -h localhost -u bhromon_user -p"$BHROMON_DB_PASSWORD" bhromon_db > "$MY_FILE" 2>/dev/null
fi
if [ -s "$MY_FILE" ]; then
    gzip -f "$MY_FILE"
    echo "MySQL backup completed: ${MY_FILE}.gz"
else
    rm -f "$MY_FILE"
fi

# 3. Backup Bhromon VPS SQLite Metadata Databases (Chat, News, Quiz)
META_DIR="/var/www/bhromon-media-meta"
SQLITE_BACKUP="$BACKUP_DIR/sqlite_bhromon_${TIMESTAMP}.tar.gz"
if [ -d "$META_DIR" ]; then
    echo "[$(date)] Starting Bhromon SQLite metadata backup..."
    tar -czf "$SQLITE_BACKUP" -C "$META_DIR" .
    echo "SQLite backup completed: $SQLITE_BACKUP"
fi

# 4. Upload to Google Drive using Rclone (if remote exists)
if command -v rclone &> /dev/null && rclone listremotes | grep -q "^gdrive:"; then
    echo "[$(date)] Syncing backups to Google Drive..."
    rclone copy "$BACKUP_DIR" "$GDRIVE_REMOTE" --max-depth 1
    echo "SUCCESS: Backups uploaded to Google Drive"
else
    echo "INFO: Rclone remote not configured, keeping backups locally in $BACKUP_DIR"
fi

# 5. Clean up local backups older than 7 days
find "$BACKUP_DIR" -type f \( -name "*.gz" -o -name "*.tar.gz" \) -mtime +7 -delete
echo "[$(date)] Cleanup of local backups older than 7 days completed."
