#!/bin/sh
# /metrics 스냅샷을 epoch 프리픽스 붙여 일별 파일로 적재한다.
# Redis의 메트릭은 누적치라 시간축이 없음 → 이 적재본으로 임의 두 시점의 차분을 내면
# "그 구간의 평균 지연/호출수"를 복원할 수 있다 (Grafana 붙기 전까지의 poor man's TSDB).
#
# 설치(호스트 ubuntu crontab):  * * * * * /home/ubuntu/pathfinder-containers/scripts/metrics-snapshot.sh
# 사용 예 — 두 시점 사이 updateUserData 평균(ms):
#   awk '$1>=T1 && $1<=T2' /home/ubuntu/metrics-history/2026-07-18.prom \
#     | grep 'updateUserData",status="200"' | grep -E '_(sum|count)\{' ...
#   (첫/마지막 스냅샷의 sum·count 차이로 (Δsum/Δcount)*1000)

DIR=/home/ubuntu/metrics-history
mkdir -p "$DIR"
TS=$(date +%s)

docker exec pathfinder php -r 'echo file_get_contents("http://127.0.0.1:8081/metrics");' 2>/dev/null \
  | sed "s/^/$TS /" >> "$DIR/$(date +%F).prom"

# 지난 날짜 파일 압축, 14일 초과분 삭제 (하루 ~45MB → 압축 후 수 MB)
find "$DIR" -name "*.prom" -mtime +0 ! -name "$(date +%F).prom" -exec gzip -q {} \; 2>/dev/null
find "$DIR" -name "*.prom.gz" -mtime +14 -delete 2>/dev/null
