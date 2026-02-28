#!/bin/sh
DATE=$(date +"%Y-%m-%d_%H-%M-%S")
docker exec pathfinder-containers-pfdb-1 sh -c 'exec mysqldump --all-databases -uroot -p"$MYSQL_ROOT_PASSWORD"' > /backup_dir/pathfinder_database_$DATE.sql
