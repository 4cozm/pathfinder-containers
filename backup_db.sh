#!/bin/sh
BACKUP_DIR="/backup_dir/backups"

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Perform backup
docker exec pathfinder-containers-pfdb-1 sh -c 'exec mysqldump --all-databases -uroot -p"$MYSQL_ROOT_PASSWORD"' > "$BACKUP_DIR/backup.sql"
