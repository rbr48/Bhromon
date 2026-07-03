#!/bin/bash

# Configuration
BACKUP_DIR="/root/bhromon-backups"
GDRIVE_REMOTE="gdrive:Bhromon_Backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Create local backup dir if not exists
mkdir -p "$BACKUP_DIR"

# 1. Backup PostgreSQL Database
PG_FILE="$BACKUP_DIR/postgres_bhromon_${TIMESTAMP}.sql"
echo "Starting PostgreSQL backup..."
PGPASSWORD='MSrana@100400' pg_dump -h localhost -U bhromon_user -d bhromon_db -F p -f "$PG_FILE"
if [ -f "$PG_FILE" ]; then
    gzip -f "$PG_FILE"
    echo "PostgreSQL backup completed: ${PG_FILE}.gz"
else
    echo "ERROR: PostgreSQL backup failed"
fi

# 2. Backup MySQL Database
MY_FILE="$BACKUP_DIR/mysql_bhromon_${TIMESTAMP}.sql"
echo "Starting MySQL backup..."
mysqldump --no-tablespaces -h localhost -u bhromon_user -p'MSrana@100400' bhromon_db > "$MY_FILE"
if [ -f "$MY_FILE" ]; then
    gzip -f "$MY_FILE"
    echo "MySQL backup completed: ${MY_FILE}.gz"
else
    echo "ERROR: MySQL backup failed"
fi

# 3. Upload to Google Drive using Rclone
echo "Syncing backups to Google Drive..."
rclone copy "$BACKUP_DIR" "$GDRIVE_REMOTE" --max-depth 1
if [ $? -eq 0 ]; then
    echo "SUCCESS: Backups uploaded to Google Drive"
else
    echo "ERROR: Google Drive upload failed"
fi

# 4. Clean up local backups older than 7 days
find "$BACKUP_DIR" -type f -name "*.gz" -mtime +7 -delete
echo "Cleanup of local backups older than 7 days completed."
