# Pathfinder Containers — d12dfc61 이후 추가된 기능 안내

**기준 커밋:** `d12dfc615faa8acd33de2147f5351dc52eeb7e85` (Update php.ini)  
**목적:** 해당 커밋 대비 현재 저장소에 정의된 새 기능·변경 사항을 정리한 안내 문서입니다.

---

## 1. 인프라·배포

| 기능 | 설명 | 관련 파일 |
|------|------|-----------|
| **로컬 이미지 빌드** | 원격 이미지 대신 로컬에서 pathfinder·websocket 빌드 (`pathfinder:local`, `pf-websocket:local`) | `docker-compose.yml`, `pathfinder.Dockerfile`, `Dockerfile.websocket` |
| **매일 DB 백업** | cron으로 매일 06:00(Asia/Seoul) DB 덤프 실행 | `pf-cron` 서비스, `backup_db.sh`, `restore_db.sh` |
| **www 서브도메인** | Traefik 라우터에서 www 제거·단순화 (호스트 규칙만 사용) | `docker-compose.yml` |
| **Ubuntu 24 한 방 설정** | Ubuntu 22/24에서 Docker·의존성·저장소 클론·설정까지 한 번에 수행 | `scripts/setup-ubuntu24.sh` |
| **Windows 빌드 스크립트** | Node 12 + npm + gulp 빌드 후 Docker 기동 (선택적 검증) | `pws.ps1` |
| **Linux 배포 스크립트** | Linux에서 빌드·배포 파이프라인 | `pws.sh` |
| **Traefik 업그레이드** | v2.3 → v2.11, 라우터 규칙 정리 | `docker-compose.yml` |
| **환경 파일 보호** | `.env`, `environment.ini` 등 git 추적 제외 | `.gitignore` |

---

## 2. Docker Compose 서비스·리소스

| 서비스 | 역할 | 비고 |
|--------|------|------|
| **pf-migrate-standalone** | standalone_detect(유저 관계도)용 테이블 1회 마이그레이션 | `standalone_detect_characters.sql`, `standalone_detect_log.sql`, `scripts/migrate-standalone-detect.sh` |
| **pf-daemon** | `standalone-daemon.php` 10초 주기 실행 | pathfinder 서브모듈의 스탠드얼론 데몬 |
| **pf-cron** | 매일 `backup_db.sh` 실행 | docker:cli 이미지, crond 사용 |
| **메모리 제한** | pfdb 550m, redis 150m, pf-socket 200m, pf 400m, pf-daemon 200m, traefik 100m, pf-cron 64m | OOM 방지·리소스 예측 가능 |
| **Redis 정책** | `maxmemory 128mb`, `allkeys-lru` | 메모리 상한·축소 정책 |
| **공유 볼륨** | `pf_tmp`, `standalone_ticket`, `./logs` 등 | 웹·소켓·데몬 간 일관된 경로 |
| **environment.ini** | `config/pathfinder/environment.ini` → `templateEnvironment.ini` 마운트 | 스탠드얼론·Discord 등 선택 설정 |

---

## 3. 환경 설정 (.env)

- **필수:** `PROJECT_ROOT`, `CONTAINER_NAME`, `DOMAIN`, `APP_PASSWORD`, DB/Redis/Pathfinder Socket, CCP SSO, `LE_EMAIL`
- **선택(스탠드얼론·Discord):**  
  `PF_STANDALONE_SECRET`, `PF_PING_JWT_SECRET`, `DISCORD_TO_PF_HMAC`, `DISCORD_ALERT_WEBHOOK_URL`
- **선택(SMTP):** `SMTP_*` 항목들
- **Redis:** `REDIS_DSN=tcp://redis:6379` 추가

---

## 4. 스탠드얼론·유저 관계도

- **DB 스키마:** `standalone_detect_characters`, `standalone_detect_log` (pathfinder 서브모듈 export SQL)
- **마이그레이션:** `pf-migrate-standalone` 서비스로 1회 적용
- **Admin/DB 진단:** 스탠드얼론·마이그레이션 관련 진단·안정화 반영
- **문서:** 유저 관계도, Admin/DB/마이그레이션 문서 및 설정 반영

---

## 5. Discord·웹훅

- Discord 웹훅 설정 (버전 알림, DmcHelper 연동)
- 환경 변수: `DISCORD_ALERT_WEBHOOK_URL`, `DISCORD_TO_PF_HMAC` 등 (선택)
- pathfinder·websocket 서브모듈에서 웜홀 질량·전투 집계 등 웹훅 이벤트 연동

---

## 6. 맵·프론트엔드·권한

- **맵 페이지 통신:** 주기적 API(맵 데이터/유저 데이터) + WebSocket으로 서버와 실시간 통신
- **맵 편집 권한:** 편집 권한이 있으면 연결/시스템 삭제 허용
- **어드민:** 어드민 기능 추가
- **전투 집계·알림:** 전투 집계 API, WS 브로드캐스트, 프론트 토스트
- **전투 로그:** 전투 로그 분석 요청 및 WebSocket 브로드캐스트
- **실시간 토큰:** websocket 모듈 실시간 토큰 대응
- **스탠드얼론 UI:** 스탠드얼론 디자인 완료, dmc_helper UI 개편·문서 반영

---

## 7. 웹소켓 서비스

- **Dockerfile.websocket:** PHP 8.3-cli-alpine 기반, sockets/pcntl/zip/bz2/pdo_mysql, Composer, `websocket` 서브모듈 빌드
- **이미지:** 로컬 빌드 `pf-websocket:local`, 컨테이너명 `pf-socket`
- **경로:** `./websocket` 서브모듈, `entrypoint.sh` → `php cmd.php`

---

## 8. 기타 버그 수정·콘텐츠

- 이중 질량 계산 버그, 웜홀 질량 로그 중복 방지
- 선박 이미지 버그, 분서갱유 관련 수정
- 맵/콘텐츠: 엔소 인더스트리, Isekai Delivery Service, Nameless Terror, 물고기 추가, 지타 연결 제거
- 버전 GET 수정, CI 메시지 출력, Diff for 파일 삭제 등

---

## 9. 참고 — 주요 파일·경로

- **빌드·실행:** `pws.ps1` (Windows), `pws.sh` (Linux), `scripts/setup-ubuntu24.sh` (Ubuntu 24)
- **백업·복원:** `backup_db.sh`, `restore_db.sh`, `backups/`
- **마이그레이션:** `scripts/migrate-standalone-detect.sh`, pathfinder 서브모듈 `export/sql/standalone_detect_*.sql`
- **설정:** `.env.example`, `config/pathfinder/pathfinder.ini`, `config/pathfinder/environment.ini`
- **스키마 패치:** `scripts/patch-schema-dt-json.php` (필요 시)

---

*이 문서는 커밋 `d12dfc615faa8acd33de2147f5351dc52eeb7e85` 이후 변경 사항을 기준으로 작성되었습니다. 세부 동작은 pathfinder·websocket 서브모듈 및 각 설정 파일을 참고하세요.*
