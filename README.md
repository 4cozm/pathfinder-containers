# Pathfinder Containers (DMC Orchestration)

**Pathfinder 코어와 확장 시스템(WebSocket, Standalone Bridge)의 통합 배포 및 운영 자동화 시스템**
- PHP 웹 서비스, Node.js WebSocket 서버, MariaDB, Redis를 컨테이너 단위로 구조화하여 Traefik 역방향 프록시를 통해 제공

## 1. 왜 이 프로젝트가 필요한가
- **배포 복잡성 해소:** PHP-FPM, Nginx, Redis, WebSocket 서버 등 다수의 의존성 서비스를 수동으로 설정할 때 발생하는 환경 파편화 문제 해결.
- **운영 안정성 결여:** 프로세스 모니터링 부재로 인한 서비스 중단 및 수동 백업에 따른 데이터 유실 위험 제거.
- **확장 기능 통합:** "DMC Helper" 등 로컬 연동 기능을 위한 데이터베이스 스키마와 소켓 서버 설정을 코어 서비스와 함께 일관되게 관리.

## 2. 핵심 제약
- **하드웨어 리소스 제한:** 저사양 VPS 환경 운영을 전제로 하며, 서비스별 메모리 점유율을 엄격하게 통제해야 함.
- **보안 요구사항:** EVE Online SSO 인증을 위해 모든 외부 통신은 HTTPS로 강제하며, SSL 인증서 발급이 자동화되어야 함.
- **데이터 영속성:** 컨테이너 생명주기와 무관하게 세션(Redis), 맵 데이터(DB), 로그 파일이 영구 저장소에 보존되어야 함.

## 3. 해결 전략
- **Docker-Compose 기반 오케스트레이션:** 모든 서비스를 컨테이너화하고 내부 네트워크(pf)와 외부 네트워크(web)를 분리하여 보안 계층화.
- **리소스 쿼터 할당:** `mem_limit` 설정을 통해 특정 서비스의 이상 동작이 전체 시스템 가용성에 영향을 주지 않도록 격리.
- **데이터베이스 프로비저닝 자동화:** `pf-migrate-standalone` 서비스를 도입하여 확장 기능용 테이블 DDL을 배포 시점에 자동 실행.
- **SSL 자동화:** Traefik과 Let's Encrypt를 통합하여 도메인 기반 라우팅 및 인증서 관리 자동화.

## 4. 아키텍처 / 데이터 흐름

```ascii
[External Request]
      |
[Traefik (SSL Termination / Routing)]
      |
      +----(HTTP 80/443)----> [Nginx (Pathfinder App)]
      |                           |
      |                     [PHP-FPM (Core Logic)] <-----> [Redis (Cache/Session)]
      |                           |
      |                           +----------------------> [MariaDB (Main Storage)]
      |
      +----(WebSocket 5555)--> [Node.js (PF-Socket)] <-----> [MariaDB (Migration Data)]
```

## 5. 설치 및 초기 설정 (Installation)

### 5.1 사전 준비
1. **EVE Developer Portal**에서 새로운 Application 생성
   - **Connection Type:** Authentication & API Access
   - **Permissions:** 아래 스코프 필수 포함
     - `esi-location.read_online.v1`, `esi-location.read_location.v1`, `esi-location.read_ship_type.v1`
     - `esi-ui.write_waypoint.v1`, `esi-ui.open_window.v1`
     - `esi-universe.read_structures.v1`, `esi-search.search_structures.v1`
     - `esi-corporations.read_corporation_membership.v1`, `esi-clones.read_clones.v1`, `esi-characters.read_corporation_roles.v1`
   - **Callback URL:** `https://[YOUR_DOMAIN]/sso/callbackAuthorization`

### 5.2 배포 순서
1. **저장소 클론 (서브모듈 포함):**
   ```shell
   git clone --recurse-submodules https://github.com/goryn-clade/pathfinder-containers.git
   ```
2. **환경 변수 설정:** `.env.example`을 복사하여 `.env` 생성 후 `PROJECT_ROOT`(절대 경로), `DOMAIN`, EVE SSO 키 값 입력.
3. **서비스 실행:**
   ```shell
   docker network create web && docker-compose up -d
   ```
4. **데이터베이스 초기화:**
   - `https://[DOMAIN]/setup` 접속 (ID: `pf`, PW: `.env`에 설정한 `APP_PASSWORD`)
   - `pf`, `eve_universe` 데이터베이스 생성 및 테이블 설정 버튼 클릭.
5. **Universe Dump 데이터 주입:**
   ```shell
   docker-compose exec pfdb /bin/sh -c "unzip -p eve_universe.sql.zip | mysql -u root -p\$MYSQL_ROOT_PASSWORD eve_universe";
   ```

## 6. 주요 구현 포인트

### 6.1 리소스 할당 최적화
- MariaDB(550m), PHP-FPM(500m), WebSocket(200m) 등 런타임 특성에 맞춰 메모리 상한을 할당하여 시스템 전체 안정성 확보.

### 6.2 마이그레이션 및 데몬 프로세스
- `pf-migrate-standalone`: 확장 기능 전용 테이블(`standalone_detect_characters` 등)의 DDL을 자동 관리.
- `pf-daemon`: 백엔드에서 맵 갱신 및 데이터 정리를 수행하는 `standalone-daemon.php`를 상시 실행 상태로 유지.

### 6.3 운영 도구 통합
- `collect_pathfinder_debug.sh`: 장애 시 컨테이너 로그, 리소스 상태, DB 진단 정보를 즉시 수집하는 자동화 도구.
- `pf-cron`: 매일 오전 6시 자동 DB 백업 수행 및 결과 로깅.

## 7. 트레이드오프와 한계
- **운영 복잡도 vs 관리 편의성:** Traefik 통합으로 초기 설정은 복잡하나, 운영 단계에서 SSL 갱신 및 서비스 추가가 용이함.
- **단일 호스트 구조:** 수평적 확장보다는 단일 노드 내에서의 안정적인 운영과 저비용 자가 호스팅에 초점을 맞춤.

## 8. 사용 기술
- **Orchestration:** Docker Compose
- **Web/Proxy:** Nginx, Traefik (v2.11)
- **Database/Cache:** MariaDB, Redis (6.2)
- **Runtime:** PHP 7.4 (FPM), Node.js (Websocket)

## 9. 라이선스 및 참고
- 본 프로젝트는 [techfreak/pathfinder-container](https://gitlab.com/techfreak/pathfinder-container/)를 기반으로 한 포크 버전입니다.
- **License:** MIT License - 상세 내용은 [LICENSE.md](LICENSE.md) 참고.
- **Author:** techfreak, johnschultz, samoneilll, 4cozm (DMC Extensions)
