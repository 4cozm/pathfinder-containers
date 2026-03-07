#!/usr/bin/env bash
set -e
crontab /var/crontab.txt
envsubst '$DOMAIN' </etc/nginx/templateSite.conf >/etc/nginx/sites_enabled/site.conf
envsubst '$PATHFINDER_SOCKET_HOST' </etc/nginx/templateNginx.conf >/etc/nginx/nginx.conf
envsubst '${DOMAIN} ${CCP_SSO_CLIENT_ID} ${CCP_SSO_SECRET_KEY} ${CCP_ESI_SCOPES} ${PATHFINDER_SOCKET_HOST} ${PATHFINDER_SOCKET_PORT} ${MYSQL_HOST} ${MYSQL_PORT} ${MYSQL_USER} ${MYSQL_PASSWORD} ${MYSQL_PF_DB_NAME} ${MYSQL_UNIVERSE_DB_NAME} ${MYSQL_CCP_DB_NAME} ${PF_STANDALONE_SECRET} ${DISCORD_WEBHOOK_IT_PING} ${DISCORD_ALERT_WEBHOOK_URL}' \
  </var/www/html/pathfinder/app/templateEnvironment.ini \
  >/var/www/html/pathfinder/app/environment.ini

envsubst  </var/www/html/pathfinder/app/templateConfig.ini >/var/www/html/pathfinder/app/config.ini
envsubst  </etc/zzz_custom.ini >/etc/php7/conf.d/zzz_custom.ini
htpasswd   -c -b -B  /etc/nginx/.setup_pass pf "$APP_PASSWORD"
exec "$@"
