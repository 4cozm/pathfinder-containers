#!/bin/sh

# 데이터베이스 복구 스크립트
# 사용법: ./restore_db.sh [백업_파일명]
# 기본값: backup.sql

FILENAME=${1:-"backup.sql"}

# 파일 경로 설정 (backups/ 폴더 내 파일 확인)
BACKUP_FILE="backups/$FILENAME"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "에러: 백업 파일을 찾을 수 없습니다: $BACKUP_FILE"
    exit 1
fi

echo "데이터베이스 복구를 시작합니다: $BACKUP_FILE"

# Docker 컨테이너 이름을 docker-compose 구성에 따라 확인해야 함
# 여기서는 기존 backup_db.sh에서 사용하던 이름을 따릅니다.
CONTAINER_NAME="pathfinder-containers-pfdb-1"

# 백업 파일 내용을 컨테이너 안의 mysql로 전달
cat "$BACKUP_FILE" | docker exec -i "$CONTAINER_NAME" sh -c 'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD"'

if [ $? -eq 0 ]; then
    echo "데이터베이스 복구가 성공적으로 완료되었습니다."
else
    echo "에러: 데이터베이스 복구에 실패했습니다."
    exit 1
fi
