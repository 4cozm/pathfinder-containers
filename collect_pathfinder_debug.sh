#!/usr/bin/env bash
set -u

APP_CONTAINER="${APP_CONTAINER:-pathfinder}"
DB_CONTAINER="${DB_CONTAINER:-pathfinder-containers-pfdb-1}"
REDIS_CONTAINER="${REDIS_CONTAINER:-redis}"
TRAEFIK_CONTAINER="${TRAEFIK_CONTAINER:-traefik}"
WS_CONTAINER="${WS_CONTAINER:-pf-socket}"

SINCE="${SINCE:-30m}"
TAIL_LINES="${TAIL_LINES:-200}"
STATS_SAMPLES="${STATS_SAMPLES:-5}"
STATS_INTERVAL="${STATS_INTERVAL:-1}"

section() {
  echo
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

run() {
  echo
  echo "\$ $*"
  bash -lc "$*" 2>&1 || true
}

section "0. BASIC INFO"
run "date"
run "docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'"

section "1. APP CONTAINER MEMORY / RESTART / OOM"
run "docker inspect ${APP_CONTAINER} --format 'Name={{.Name}} RestartCount={{.RestartCount}} OOMKilled={{.State.OOMKilled}} Error={{.State.Error}}'"
run "docker inspect ${APP_CONTAINER} --format 'Memory={{.HostConfig.Memory}} MemorySwap={{.HostConfig.MemorySwap}} OOMKillDisable={{.HostConfig.OomKillDisable}}'"
run "docker stats --no-stream ${APP_CONTAINER}"

section "1B. APP CONTAINER SHORT STATS SAMPLES"
run "for i in \$(seq 1 ${STATS_SAMPLES}); do date '+%F %T'; docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.PIDs}}' ${APP_CONTAINER}; sleep ${STATS_INTERVAL}; done"

section "2. NGINX ERROR LOG (APP CONTAINER)"
run "docker exec ${APP_CONTAINER} sh -lc 'tail -n ${TAIL_LINES} /var/log/nginx/error.log'"

section "3. NGINX ACCESS 4xx/5xx (APP CONTAINER)"
run "docker exec ${APP_CONTAINER} sh -lc 'tail -n ${TAIL_LINES} /var/log/nginx/access.log | egrep \" 4[0-9][0-9] | 5[0-9][0-9] \"'"

section "4. APP CONTAINER STDOUT/STDERR"
run "docker logs --since ${SINCE} ${APP_CONTAINER} | tail -n ${TAIL_LINES}"

section "5. SUPERVISOR LOG"
run "docker exec ${APP_CONTAINER} sh -lc 'tail -n ${TAIL_LINES} /var/www/html/supervisord.log'"

section "5B. SUPERVISOR STATUS"
run "docker exec ${APP_CONTAINER} sh -lc 'supervisorctl status 2>/dev/null || true'"

section "6. PHP-FPM PROCESS TREE / RSS"
run "docker exec ${APP_CONTAINER} sh -lc 'ps -o pid,ppid,rss,vsz,args | grep php-fpm | grep -v grep'"

section "6B. APP LISTEN PORTS / SOCKET STATE"
run "docker exec ${APP_CONTAINER} sh -lc 'ss -lntp 2>/dev/null | grep -E \"[:](80|9000|8020)([^0-9]|$)\" || netstat -lntp 2>/dev/null | grep -E \"[:](80|9000|8020)([^0-9]|$)\" || true'"

section "6C. PHP-FPM WORKER SUMMARY"
run "docker exec ${APP_CONTAINER} sh -lc 'ps -o pid,ppid,state,rss,args | grep php-fpm | grep -v grep; echo; echo -n \"php-fpm process count=\"; ps -ef | grep php-fpm | grep -v grep | wc -l'"

section "7. NGINX PROCESS TREE / RSS"
run "docker exec ${APP_CONTAINER} sh -lc 'ps -o pid,ppid,rss,vsz,args | grep nginx | grep -v grep'"

section "8. PHP-FPM EFFECTIVE CONFIG"
run "docker exec ${APP_CONTAINER} sh -lc 'php-fpm7 -tt 2>&1 | egrep \"pm =|pm.max_children|pm.max_requests|pm.process_idle_timeout|request_terminate_timeout|memory_limit|listen =|pm.status_path\"'"

section "9. KEY CONFIG FILES"
run "docker exec ${APP_CONTAINER} sh -lc 'echo \"--- /etc/php7/php-fpm.d/zzz_custom.conf\"; sed -n \"1,220p\" /etc/php7/php-fpm.d/zzz_custom.conf 2>/dev/null; echo; echo \"--- /etc/php7/conf.d/zzz_custom.ini\"; sed -n \"1,220p\" /etc/php7/conf.d/zzz_custom.ini 2>/dev/null; echo; echo \"--- /etc/supervisor/conf.d/supervisord.conf\"; sed -n \"1,220p\" /etc/supervisor/conf.d/supervisord.conf 2>/dev/null'"

section "10. MYSQL CONNECTIVITY FROM APP"
run "docker exec ${APP_CONTAINER} sh -lc 'getent hosts mariadb || ping -c 1 mariadb || true'"
run "docker exec ${APP_CONTAINER} sh -lc 'nc -vz mariadb 3306 2>&1 || true'"

section "11. DB STATUS"
run "docker exec ${DB_CONTAINER} sh -lc 'mysql -uroot -prootpass -e \"SHOW GLOBAL STATUS LIKE '\''Threads_connected'\''; SHOW GLOBAL STATUS LIKE '\''Aborted_connects'\''; SHOW GLOBAL STATUS LIKE '\''Aborted_clients'\''; SHOW GLOBAL VARIABLES LIKE '\''max_connections'\''; SHOW GLOBAL VARIABLES LIKE '\''wait_timeout'\''; SHOW GLOBAL VARIABLES LIKE '\''interactive_timeout'\''; SHOW GLOBAL VARIABLES LIKE '\''max_allowed_packet'\'';\"'"

section "12. REDIS STATUS"
run "docker exec ${REDIS_CONTAINER} sh -lc 'redis-cli ping; echo; redis-cli info clients | egrep \"connected_clients|blocked_clients\"; echo; redis-cli info memory | egrep \"used_memory_human|maxmemory_human\"'"

section "13. TRAEFIK RECENT LOGS"
run "docker logs --since ${SINCE} ${TRAEFIK_CONTAINER} | tail -n ${TAIL_LINES}"

section "14. PATHFINDER KEYWORDS"
run "docker logs --since ${SINCE} ${APP_CONTAINER} 2>&1 | egrep -i 'php-fpm|SIGKILL|OOM|MySQL server has gone away|server reached pm.max_children|pool seems busy|error|warning|fatal' | tail -n ${TAIL_LINES}"
run "docker exec ${APP_CONTAINER} sh -lc 'tail -n ${TAIL_LINES} /var/log/nginx/error.log | egrep -i \"upstream|reset by peer|timed out|502|503|504|500\"'"

section "15. PATHFINDER APP LOGS"
run "docker exec ${APP_CONTAINER} sh -lc 'ls -lh /var/www/html/pathfinder/logs/ && tail -n ${TAIL_LINES} /var/www/html/pathfinder/logs/*.log 2>/dev/null'"

section "16. WEBSOCKET LOGS"
run "docker logs --since ${SINCE} ${WS_CONTAINER} | tail -n ${TAIL_LINES}"

section "16B. WEBSOCKET PROCESS / PORT"
run "docker exec ${WS_CONTAINER} sh -lc 'ps -o pid,ppid,state,rss,args; echo; ss -lntp 2>/dev/null | grep :8020 || netstat -lntp 2>/dev/null | grep :8020 || true'"

section "16C. WEBSOCKET KEYWORDS"
run "docker logs --since ${SINCE} ${WS_CONTAINER} 2>&1 | egrep -i 'error|warn|fatal|exception|EADDRINUSE|ECONNRESET|listen|SIGTERM|SIGKILL|OOM|restart|exit' | tail -n ${TAIL_LINES}"

section "17. PHP ERROR LOG / MAX_INPUT_VARS CHECK"
run "docker exec ${APP_CONTAINER} sh -lc 'tail -n ${TAIL_LINES} /var/log/php7/error.log | egrep -i \"max_input_vars|memory_limit|timeout\"'"

section "17B. PHP-FPM KEY EVENTS"
run "docker exec ${APP_CONTAINER} sh -lc '
for f in /var/log/php7/error.log /var/log/php*/error.log /var/log/*php*fpm*log; do
  [ -f \"\$f\" ] || continue
  echo \"--- \$f\"
  tail -n ${TAIL_LINES} \"\$f\" 2>/dev/null | grep -Ei \"max_children|pool seems busy|child.*exited|child.*signal|SIGSEGV|segfault|killed|terminate|oom|backlog|listen queue|server reached pm.max_children\" || true
done
'"

section "18. HOST OOM / KERNEL KILL SIGNS (OPTIONAL)"
run "dmesg -T 2>/dev/null | egrep -i 'killed process|out of memory|oom' | tail -n ${TAIL_LINES}"
run "journalctl -k --since '-${SINCE}' 2>/dev/null | egrep -i 'killed process|out of memory|oom' | tail -n ${TAIL_LINES}"

section "19. PHP-FPM STATUS (DIRECT)"
# active=0 은 정상 유휴 상태일 수 있음. listen queue > 0 일 때만 worker 포화로 해석권장.
run "docker exec ${APP_CONTAINER} sh -lc 'SCRIPT_NAME=/fpm-status SCRIPT_FILENAME=/fpm-status QUERY_STRING=json REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000 || echo \"cgi-fcgi failed (check if fcgi package is installed)\"'"

section "20. DB FULL PROCESSLIST (LOCK CHECK)"
# 목록이 깨끗하다고 해서 앱 로직 부하로 단정 금지. 단지 DB 병목 가능성이 낮음을 시사.
run "docker exec ${DB_CONTAINER} sh -lc 'mysql -uroot -prootpass -e \"SHOW FULL PROCESSLIST;\"'"

section "21. KERNEL TCP STATS (OVERFLOW/DROP)"
# ListenDrops 는 커널 레벨 드랍임. Nginx/App 레벨의 refused와는 별개로 분석 요망.
run "docker exec ${APP_CONTAINER} sh -lc 'netstat -s | grep -Ei \"listen|drop|overflow\"'"

section "22. LISTEN PORT STATE (SS)"
# 프로세스가 실제로 포트를 점유하고 있는지(Listening) 최종 확인.
run "docker exec ${APP_CONTAINER} sh -lc 'ss -lntp 2>/dev/null | grep -E \"(80|9000|8020)\"'"

section "23. FATAL/MEMORY ERROR LOG (DETAILED)"
# memory_limit exhausted 등의 명시적 로그가 있을 때만 앱 자폭 가설을 확정함.
run "docker exec ${APP_CONTAINER} sh -lc 'grep -Ei \"fatal|memory_limit|exhausted|segfault|sigsegv\" /var/log/php*/error.log /var/log/nginx/error.log 2>/dev/null | tail -n ${TAIL_LINES}'"

section "24. 3-SHOT LIVE STATS (TRENDING)"
# 단독 확정 근거로 사용 금지. 자원 사용량의 급격한 증감 추이(Trend) 확인용.
run "for i in 1 2 3; do echo \"--- Sample \$i (\$(date +%T))\"; docker stats --no-stream --format \"table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}\"; sleep 5; done"
