#!/bin/sh
# 유저 관계도용 테이블 standalone_detect_characters DDL 1회 실행.
# docker-compose의 pf-migrate-standalone 서비스에서 사용.
# 환경변수: MYSQL_HOST, MYSQL_PORT(선택, 기본 3306), MYSQL_USER, MYSQL_PASSWORD, MYSQL_PF_DB_NAME(선택, 기본 pathfinder)

set -e

HOST="${MYSQL_HOST:-pfdb}"
PORT="${MYSQL_PORT:-3306}"
USER="${MYSQL_USER:-root}"
DB="${MYSQL_PF_DB_NAME:-pathfinder}"
export MYSQL_PWD="${MYSQL_PASSWORD:?MYSQL_PASSWORD is required}"

echo "Waiting for MySQL at $HOST:$PORT..."
until mysql -h "$HOST" -P "$PORT" -u "$USER" -e "SELECT 1" 2>/dev/null; do
  echo "  still waiting..."
  sleep 2
done

echo "Ensuring database $DB exists..."
mysql -h "$HOST" -P "$PORT" -u "$USER" -e "CREATE DATABASE IF NOT EXISTS \`$DB\`;"

for f in /sql/standalone_detect_characters.sql /sql/standalone_detect_log.sql; do
  if [ -f "$f" ]; then
    echo "Running $f on database $DB..."
    mysql -h "$HOST" -P "$PORT" -u "$USER" "$DB" < "$f"
  fi
done
echo "standalone_detect migration done."
