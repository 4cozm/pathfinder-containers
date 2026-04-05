#!/usr/bin/env bash
set -u

APP_CONTAINER="${APP_CONTAINER:-pathfinder}"
DB_CONTAINER="${DB_CONTAINER:-pathfinder-containers-pfdb-1}"
REDIS_CONTAINER="${REDIS_CONTAINER:-redis}"
TRAEFIK_CONTAINER="${TRAEFIK_CONTAINER:-traefik}"

SINCE="${SINCE:-30m}"
TAIL_LINES="${TAIL_LINES:-200}"

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

section "2. NGINX ERROR LOG (APP CONTAINER)"
run "docker exec ${APP_CONTAINER} sh -lc 'tail -n ${TAIL_LINES} /var/log/nginx/error.log'"

section "3. NGINX ACCESS 4xx/5xx (APP CONTAINER)"
run "docker exec ${APP_CONTAINER} sh -lc 'tail -n ${TAIL_LINES} /var/log/nginx/access.log | egrep \" 4[0-9][0-9] | 5[0-9][0-9] \"'"

section "4. APP CONTAINER STDOUT/STDERR"
run "docker logs --since ${SINCE} ${APP_CONTAINER} | tail -n ${TAIL_LINES}"

section "5. SUPERVISOR LOG"
run "docker exec ${APP_CONTAINER} sh -lc 'tail -n ${TAIL_LINES} /var/www/html/supervisord.log'"

section "6. PHP-FPM PROCESS TREE / RSS"
run "docker exec ${APP_CONTAINER} sh -lc 'ps -o pid,ppid,rss,vsz,args | grep php-fpm | grep -v grep'"

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
run "docker logs --since ${SINCE} pf-socket | tail -n ${TAIL_LINES}"

section "17. PHP ERROR LOG / MAX_INPUT_VARS CHECK"
run "docker exec ${APP_CONTAINER} sh -lc 'tail -n ${TAIL_LINES} /var/log/php7/error.log | egrep -i \"max_input_vars|memory_limit|timeout\"'"
