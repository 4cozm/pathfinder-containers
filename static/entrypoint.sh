#!/usr/bin/env bash
set -e

# Fix nginx directory permissions (Root Cause of 403)
chown -R nobody:nobody /var/log/nginx /var/lib/nginx
chmod -R 755 /var/log/nginx /var/lib/nginx

# Fix PHP app logs permission for Docker bind mounts
chown -R nobody:nobody /var/www/html/pathfinder/logs /var/www/html/pathfinder/tmp
chmod -R 775 /var/www/html/pathfinder/logs /var/www/html/pathfinder/tmp
crontab /var/crontab.txt
envsubst '${DOMAIN} ${PATHFINDER_SOCKET_HOST}' </etc/nginx/templateSite.conf >/etc/nginx/sites_enabled/site.conf
envsubst '$PATHFINDER_SOCKET_HOST' </etc/nginx/templateNginx.conf >/etc/nginx/nginx.conf
# envsubst 의 첫 인자는 "치환 허용 목록"이다. 여기에 없는 ${VAR} 는 치환되지 않고
# 리터럴 문자열 그대로 environment.ini 에 남는다(값이 있는 것처럼 보이므로 더 위험하다).
# 새 환경변수를 templateEnvironment.ini 에 추가하면 반드시 이 목록에도 추가할 것.
envsubst '${DOMAIN} ${CCP_SSO_CLIENT_ID} ${CCP_SSO_SECRET_KEY} ${CCP_ESI_SCOPES} ${PATHFINDER_SOCKET_HOST} ${PATHFINDER_SOCKET_PORT} ${MYSQL_HOST} ${MYSQL_PORT} ${MYSQL_USER} ${MYSQL_PASSWORD} ${MYSQL_PF_DB_NAME} ${MYSQL_UNIVERSE_DB_NAME} ${MYSQL_CCP_DB_NAME} ${PF_STANDALONE_SECRET} ${DISCORD_WEBHOOK_IT_PING} ${DISCORD_ALERT_WEBHOOK_URL} ${REDIS_HOST} ${REDIS_PORT} ${REDIS_AUTH}' \
  </var/www/html/pathfinder/app/templateEnvironment.ini \
  >/var/www/html/pathfinder/app/environment.ini

envsubst  </var/www/html/pathfinder/app/templateConfig.ini >/var/www/html/pathfinder/app/config.ini
envsubst  </etc/zzz_custom.ini >/etc/php7/conf.d/zzz_custom.ini
htpasswd   -c -b -B  /etc/nginx/.setup_pass pf "$APP_PASSWORD"
exec "$@"
