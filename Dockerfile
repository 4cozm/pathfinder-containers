FROM ghcr.io/goryn-clade/pathfinder:latest

# 로컬 composer.lock 기준으로 vendor 갱신 (베이스 이미지 vendor만 쓰면 DT_JSON 등 누락 가능)
# pws.ps1/루트 빌드용. 수동 빌드는 pathfinder.Dockerfile에서 동일 DT_JSON 패치 적용함.
COPY ./pathfinder/composer.json ./pathfinder/composer.lock /var/www/html/pathfinder/
# php7-opcache: 업스트림 이미지에 누락 — 없으면 요청마다 전체 PHP 재컴파일 (CPU 병목 실측)
# --optimize-autoloader: 오토로더 classmap 생성 — 디스크 스캔 기반 클래스 탐색 제거
RUN apk add --no-cache curl unzip fcgi logrotate php7-opcache \
 && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
 && cd /var/www/html/pathfinder && rm -rf vendor && composer install --no-dev --no-scripts --no-interaction --optimize-autoloader \
 && apk del curl unzip

COPY ./scripts/patch-schema-dt-json.php /tmp/patch-schema-dt-json.php
RUN php /tmp/patch-schema-dt-json.php /var/www/html/pathfinder/vendor/ikkez/f3-schema-builder/lib/db/sql/schema.php \
 && php -r "require '/var/www/html/pathfinder/vendor/autoload.php'; if (!(new ReflectionClass('DB\SQL\Schema'))->hasConstant('DT_JSON')) { echo 'BUILD FAIL: DT_JSON missing from Schema\n'; exit(1); } echo 'Schema::DT_JSON OK\n';"

COPY ./pathfinder/app /var/www/html/pathfinder/app
# public 전체 복사 (css/v2.2.4 없어도 빌드 성공 — 서브모듈에 없을 수 있음)
COPY ./pathfinder/public/. /var/www/html/pathfinder/public/

# tmp 권한 + 구버전 precompressed(.br, .gz) 파일 제거 (디렉터리 없으면 무시)
RUN (test -d /var/www/html/pathfinder/public/js/v2.2.4 && find /var/www/html/pathfinder/public/js/v2.2.4 -type f \( -name "*.br" -o -name "*.gz" \) -delete) || true \
 && (test -d /var/www/html/pathfinder/public/css/v2.2.4 && find /var/www/html/pathfinder/public/css/v2.2.4 -type f \( -name "*.br" -o -name "*.gz" \) -delete) || true \
 && mkdir -p /var/www/html/pathfinder/tmp \
 && chmod -R 777 /var/www/html/pathfinder/tmp

# Inject the fixed entrypoint.sh, nginx.conf, and PHP configurations
COPY static/entrypoint.sh /entrypoint.sh
COPY static/nginx/nginx.conf /etc/nginx/templateNginx.conf
COPY static/nginx/site.conf /etc/nginx/templateSite.conf
COPY static/php/fpm-pool.conf /etc/php7/php-fpm.d/zzz_custom.conf
# 베이스 이미지 기본 풀(www.conf) 제거 — 우리 zzz_custom.conf와 [www] 풀이 중복되어
# 워커가 두 풀에서 동시에 떠 max_children(10) 상한을 우회하던 문제 방지
RUN rm -f /etc/php7/php-fpm.d/www.conf
COPY static/php/php.ini /etc/zzz_custom.ini
COPY static/php/opcache.ini /etc/php7/conf.d/zzz_opcache.ini
COPY static/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
# 관측성: nginx/app 로그 로테이션 + logrotate 크론 엔트리 (베이스 이미지 값을 덮어씀)
COPY static/logrotate/pathfinder /etc/logrotate.d/pathfinder
COPY static/crontab.txt /var/crontab.txt
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh