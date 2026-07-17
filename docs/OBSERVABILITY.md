# 관측성 (Observability) — Grafana Cloud + Alloy

사용자 보고(렉/오류)의 병목·지터 진단을 위한 관측 스택. 박스(2 vCPU / 4GB)에는
**Grafana Alloy 에이전트 하나만** 올리고, 저장/대시보드는 Grafana Cloud 무료 티어를 쓴다.

```
[pf 컨테이너] --/metrics(:8081 내부전용)--> [Alloy] --remote_write--> Grafana Cloud (Metrics)
[./logs/app, ./logs/nginx, docker stdout] --> [Alloy] --push--------> Grafana Cloud (Logs)
```

## 1. 셋업 절차

1. https://grafana.com 무료 계정 생성 → Cloud 스택 생성
2. 스택 관리 화면에서 아래 값 확인 후 `.env`에 추가 (`.env.example` 참고):
   - **Prometheus** → Remote Write Endpoint(`GCLOUD_HOSTED_METRICS_URL`), Username/Instance ID(`GCLOUD_HOSTED_METRICS_ID`)
   - **Loki** → Push Endpoint(`GCLOUD_HOSTED_LOGS_URL`), User(`GCLOUD_HOSTED_LOGS_ID`)
   - **Access Policy Token** 생성 (metrics:write + logs:write) → `GCLOUD_RW_API_KEY`
3. 이미지 재빌드 + 기동:
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d --build
   ```
4. 확인:
   ```bash
   docker exec pathfinder curl -s http://127.0.0.1:8081/metrics | head -50   # 앱 메트릭
   docker logs alloy --tail 50                                              # 전송 에러 없는지
   ```
5. Grafana Cloud → Explore에서 `pf_http_request_duration_seconds_count` 조회로 도착 확인

## 2. 관측 지표 분류표 (전수조사 결과)

### 필수 — 이번에 구현됨

| 지표 | 종류 | 위치 | 무엇을 밝히나 |
|---|---|---|---|
| `pf_http_request_duration_seconds` {route,method,status} | histogram | `Controller::unload()` | 요청별 지연 분포·지터. 에러 응답 포함 전 요청 관측 |
| `pf_session_start_seconds` | histogram | `Controller::initSession()` | **세션 행 잠금 대기** — mysql 세션 + 5초 폴링 2종 조합이 렉의 유력 원인 후보. 이 값이 크면 확정 |
| `pf_db_query_duration_seconds` {db,op} | histogram | `Lib/Db/Sql::exec()` | DB 쿼리 지연 (기존 계측 전무였음). 1s+ 쿼리는 `[SLOW_SQL]` 로그도 남김 |
| `pf_esi_request_duration_seconds` {endpoint} / `pf_esi_errors_total` | histogram/counter | `CcpClient::__call()` + `EsiRouteStatusAdapter` | 외부 ESI 지연·실패 (워커 점유 시간의 주범 후보). 어댑터 직행분은 `endpoint="adapterGetRoute\|adapterGetStatus"` |
| `pf_socket_push_duration_seconds` {task} / `pf_socket_push_failures_total` | histogram/counter | `AbstractSocket::write()` | **PHP→웹소켓 push는 동기(블로킹)** — 소켓 서버 지연이 웹 요청을 직접 잡아먹는 구간. 실패는 기존에 조용히 삼켜졌음 |
| `pf_active_workers` | gauge | 기존 Redis 키 노출 | 동시 처리 중 요청 수 (max_children=20 대비 포화도) |
| `pf_phpfpm_*` (active/idle processes, listen queue, max children reached, slow requests) | gauge/counter | fpm status → MetricsController | php-fpm 워커 포화 — 2 vCPU 박스의 1순위 렉 신호 |
| `pf_nginx_*` (connections, requests) | gauge/counter | stub_status → MetricsController | 엣지 커넥션 상태 |
| 호스트 CPU/mem/IO (`node_*`) | — | Alloy 내장 unix exporter | CPU 포화/스틸 = 즉시 렉 |
| nginx 액세스 로그 `rt=`/`ut=` | Loki | `main_ext` 포맷 전환 | 요청별 실제 소요시간 (기존엔 2xx/3xx를 로그에서 버려서 "느린 성공"이 안 보였음) |
| 앱 에러 로그 (error/sso/socket_error) | Loki | `./logs/app` | 오류 원인 파고들기 |

### 권장 — 이번에 구현됨

| 지표 | 위치 | 무엇을 밝히나 |
|---|---|---|
| `pf_backpressure_score` | 기존 `PF_P_SKIP` 노출 | 백프레셔 계층이 요청을 죽이는 정도 |
| `pf_cron_runs_total`, `pf_cron_last_{duration,cpu}_seconds`, `pf_cron_last_mem_peak_bytes`, `pf_cron_fail_count` {job} | `AbstractCron::logEnd()` | 크론 지연/실패 (기존 cron_history 값 재사용) |
| `pf_daemon_tick_duration_seconds`, `pf_daemon_{ticks,errors,chars_processed}_total` | `standalone-daemon.php` | 데몬 틱 지연·오류 |
| Redis 메트릭 (evictions, memory, latency) | Alloy 내장 redis exporter | 세션스토어/캐시 압박 (256MB volatile-lru — eviction 발생 시 캐시·메트릭 유실) |
| 컨테이너별 메모리/CPU (`container_*`) | Alloy 내장 cadvisor | mem_limit 대비 사용량, 특히 pf-socket(200m) OOM 감시 |
| `[ws-stats]` JSON 로그 (60초 주기) | websocket `WebSockets.php` | WS 접속수/맵별 구독수/메모리 — 접속 폭주·누수 추적 |
| php-fpm slowlog (5s+) | `fpm-pool.conf` → `php_slow.log` | 느린 요청의 PHP 스택트레이스 (어느 함수에서 멈췄는지) |

### 선택 — 구현 안 함 (필요 시 활성화)

| 항목 | 활성화 방법 |
|---|---|
| MariaDB internals (mysqld exporter) | `config/alloy/config.alloy` 주석 해제 + exporter DB 유저 생성 (파일 내 주석 참고). DB가 범인으로 지목되면 켜기 |
| MariaDB slow query log / performance_schema | `my.cnf` 마운트 필요. perf_schema는 RAM 50–150MB 소모 (900m 한도 주의) |
| Traefik 메트릭 (`--metrics.prometheus=true`) | 엣지 레벨 라우터별 지연. nginx 로그와 중복이라 보류 |
| ESI 에러리밋 헤더 게이지 (`X-Esi-Error-Limit-Remain`) | vendor 패키지(goryn-clade/pathfinder_esi) 수정 필요 — 현재는 vendor가 로그로만 남김. 그 외 ESI 스펙 이슈는 [ESI_SPEC_AUDIT.md](ESI_SPEC_AUDIT.md) 참고 |
| F3 캐시 hit/miss 카운터 | 캐시 백엔드를 Redis로 바꾸는 게 먼저 (아래 §4) |

## 3. 먼저 볼 대시보드 쿼리

```promql
# 요청 p95 (route별) — 지터가 어디서 오는지
histogram_quantile(0.95, sum(rate(pf_http_request_duration_seconds_bucket[5m])) by (le, route))

# 세션 락 가설 검증 — 이 p95가 수백 ms면 렉 원인 확정
histogram_quantile(0.95, sum(rate(pf_session_start_seconds_bucket[5m])) by (le))

# php-fpm 포화 — active가 20(max_children)에 붙거나 listen_queue > 0이면 포화
pf_phpfpm_active_processes  /  pf_phpfpm_listen_queue  /  increase(pf_phpfpm_max_children_reached_total[1h])

# DB vs ESI vs socket — 워커 시간을 누가 먹는지
sum(rate(pf_db_query_duration_seconds_sum[5m]))
sum(rate(pf_esi_request_duration_seconds_sum[5m]))
sum(rate(pf_socket_push_duration_seconds_sum[5m]))
```

```logql
# 1초 이상 걸린 요청 (nginx main_ext)
{job="nginx", filename=~".*access.log"} | regexp `rt=(?P<rt>[0-9.]+)` | rt > 1.0

# 웹소켓 서버 상태 스냅샷
{job="docker", container="pf-socket"} |= "[ws-stats]"

# 느린 SQL / 소켓 push 실패
{job="docker", container="pathfinder"} |= "[SLOW_SQL]"
{job="docker", container="pathfinder"} |= "[SOCKET_PUSH_FAIL]"
```

## 4. 조사 중 발견된 성능 개선 후보 (관측으로 검증 후 적용 권장)

계측이 아니라 **설정 변경**이라 이번 작업에서는 건드리지 않았다. 메트릭으로 가설을 확인한 뒤 적용할 것.

1. **세션 저장소 mysql → Redis 전환** (`config.ini SESSION_CACHE`): F3 mysql 세션은 요청마다
   sessions 행에 `SELECT ... FOR UPDATE` 잠금. 같은 브라우저가 5초마다 2개 엔드포인트를
   동시 폴링하므로 요청이 락에서 직렬화된다 → `pf_session_start_seconds`로 검증.
2. **F3 캐시 folder → Redis 전환** (`config.ini CACHE`/`API_CACHE`): 현재 핫패스 맵 데이터와
   ESI 응답 캐시가 디스크 파일이다. config 주석조차 Redis를 권장.
3. `PF_ACTIVE_WORKERS` 드리프트는 이번에 수정함 (에러 경로에서 decrement 누락 → unload로 이동).

## 5. 구조 메모

- 앱 메트릭 저장소: Redis hash `PF_METRICS` (`app/Lib/Metrics.php`). 별도 라이브러리/컨테이너
  없이 PHP 7.2 호환. Redis가 volatile-lru라서 TTL 없는 이 키는 eviction 대상이 아님.
- `/metrics`는 `MetricsController`(Controller 미상속 — 스크레이프가 세션/워커카운트를 오염시키지
  않음)가 렌더하고, 같은 컨테이너의 `/fpm-status?json`·`/nginx_status`를 합쳐서 내보낸다.
- `/metrics`는 `:80`/`:443`에서 404, 내부 vhost `:8081`에서만 응답 (`static/nginx/site.conf`).
- fpm 풀이 완전 포화되면 `/fpm-status` 서브요청이 1초 타임아웃으로 실패할 수 있다
  (`pf_exporter_scrape_error{target="phpfpm"}`) — 그 순간에도 `pf_active_workers`(Redis 직행)는
  살아있으므로 포화 신호는 잃지 않는다.
- 로그 로테이션: 컨테이너 내 logrotate (`static/logrotate/pathfinder`, 매일 04시 crontab) —
  main_ext 전체 로깅으로 늘어난 access.log 디스크를 관리한다.
