# Pathfinder 확장 시스템 & 컨테이너 오케스트레이션

EVE Online의 위치 공유 도구인 Pathfinder의 다중 캐릭터 추적 한계를 극복하기 위한 확장 시스템과 고가용성 운영을 위한 컨테이너 오케스트레이션 통합 환경.

*   **확장 시스템**: OS 네이티브 신호를 활용하여 ESI API 호출 제한(429) 문제를 근본적으로 해결
*   **오케스트레이션**: PHP Core, WebSocket, DB, Redis 등 파편화된 의존성을 Docker로 구조화하여 배포 및 운영 자동화

## 1. 왜 이 프로젝트가 필요한가

### 1.1 확장 시스템 관점 (DMC Helper)
*   **ESI API 호출 제한 및 비용**: 기존 시스템은 웹 세션 유저의 위치 갱신을 위해 5초 주기로 ESI 폴링을 수행하며, 이는 다중 캐릭터 환경에서 API 429 에러를 유발하고 정보 정확도를 떨어뜨림.
*   **리소스 낭비 및 번거로움**: 모든 캐릭터의 위치를 갱신하려면 캐릭터 수만큼 브라우저 탭을 열어두어야 하며, 이는 불필요한 메모리 점유와 복잡한 조작을 요구함.

### 1.2 운영 관점 (Containerization)
*   **배포 복잡성 해소**: PHP-FPM, Nginx, Redis, WebSocket 서버 등 다수의 서비스를 수동 설정할 때 발생하는 환경 파편화 및 의존성 충돌 문제 해결.
*   **운영 안정성 확보**: 프로세스 모니터링 부재로 인한 중단 위험을 제거하고, 자동화된 백업 및 장애 진단 도구 통합 필요.

## 2. 핵심 제약

*   **브라우저 샌드박스**: 웹 앱은 OS의 윈도우 창 정보에 접근할 수 없어 게임 클라이언트 실행 여부를 직접 판단할 수 없음.
*   **하드웨어 및 비용 제한**: 저사양 VPS 환경에서의 운영을 전제로 하며, 서비스별 메모리 점유율을 엄격하게 통제해야 함.
*   **보안 및 신뢰 요구사항**: HTTPS 강제 및 스탠드얼론 프로그램의 요청에 대한 스푸핑/재전송 공격 방어(DPoP 도입).
*   **데이터 영속성**: 컨테이너 생명주기와 무관하게 세션, 맵 데이터, 로그 파일이 영구 저장소에 보존되어야 함.

## 3. 해결 전략

*   **네이티브 신호 기반 SOT(Source of Truth)**: 게임 클라이언트의 윈도우 창 제목(`EVE Online - [캐릭터명]`)을 온라인 상태의 결정적 신호로 채택하여 API 폴링 비용 제거.
*   **하이브리드 아키텍처**: OS 접근 권한을 가진 C# WPF 애플리케이션(Standalone)과 실시간 데이터 동기화를 위한 WebSocket 브릿지 구축.
*   **Docker-Compose 오케스트레이션**: 내부(pf)와 외부(web) 네트워크를 분리하고 리소스 쿼터(mem_limit)를 할당하여 시스템 격리 및 안정성 확보.
*   **서버리스 오프로딩**: Discord 메시지 전송 로직을 Cloudflare Workers로 분리하고, DPoP JWT와 KV를 통해 서버-Worker 간의 무상태(Stateless) 보안 검증 구현.

## 4. 아키텍처 / 데이터 흐름

```ascii
[External Request / Standalone App]
      |
[Traefik (SSL / Routing)] <---(App Scheme)--- [Browser]
      |
      +----(HTTP 80/443)----> [Nginx (Pathfinder App)]
      |                           |
      |                     [PHP-FPM (Core)] <-----> [Redis (Session)]
      |                           |
      |                           +----------------> [MariaDB (Main)]
      |
      +----(WebSocket 5555)--> [Node.js (Socket)] --(DPoP JWT)--> [CF Workers]
                                     |                             |
                             [Migration Data]               [Discord Webhook]
```

## 5. 주요 구현 포인트

### 5.1 확장 기능 및 보안
*   **DPoP + KV 검증**: 리플레이 어택 방지를 위해 KV에 `jti`를 캐싱하고, Worker 단에서 퍼블릭 ESI API를 통해 권한을 이중 체크하는 무상태 보안 구조.
*   **WS 하위 호환성**: 기존 서버 주도 관리 로직을 깨뜨리지 않고 클라이언트가 동일한 WS 인터페이스로 추적을 요구하게 하여 기존 DB 및 ESI 토큰 로직 재활용.

### 5.2 컨테이너 최적화 및 운영
*   **리소스 할당 최적화**: MariaDB(550m), PHP-FPM(500m) 등 런타임 특성에 맞춘 상한 설정으로 특정 서비스 이상 동작이 전체 시스템에 미치는 영향 차단.
*   **자동화 도구**: 장애 시 로그 및 리소스 상태를 수집하는 `collect_pathfinder_debug.sh`와 매일 자동 DB 백업을 수행하는 `pf-cron` 통합.

## 6. 운영 관점의 설계 판단

*   **버전 호환성 통제**: 백엔드에서 클라이언트 버전을 검증하여 구버전의 WebSocket 연결을 거부함으로써 클라이언트-서버 간 데이터 정합성 유지.
*   **CI/CD 기반 배포**: GitHub Actions를 통해 WPF 앱 및 컨테이너 이미지를 자동 빌드하고, 릴리즈 시 버전 간 Diff 정보를 제공하여 업데이트 편의성 확보.
*   **마이그레이션 자동화**: `pf-migrate-standalone` 서비스를 통해 확장 기능 전용 테이블 DDL을 배포 시점에 자동 실행.

## 7. 설치 및 초기 설정 (Installation)

### 7.1 사전 준비
1. **EVE Developer Portal**에서 Application 생성
   - **Scopes:** `esi-location.read_online.v1`, `esi-location.read_location.v1`, `esi-ui.write_waypoint.v1` 등 필수 권한 포함.
   - **Callback URL:** `https://[YOUR_DOMAIN]/sso/callbackAuthorization`

### 7.2 배포 순서
1. **저장소 클론 (서브모듈 포함):**
   ```shell
   git clone --recurse-submodules https://github.com/4cozm/pathfinder-containers.git
   ```
2. **환경 변수 설정:** `.env.example`을 복사하여 `.env` 생성 후 `PROJECT_ROOT`, `DOMAIN`, EVE SSO 키 입력.
3. **서비스 실행:**
   ```shell
   docker network create web && docker-compose up -d
   ```
4. **Universe Dump 데이터 주입:**
   ```shell
   docker-compose exec pfdb /bin/sh -c "unzip -p eve_universe.sql.zip | mysql -u root -p\$MYSQL_ROOT_PASSWORD eve_universe";
   ```

## 7.3 관측성 (선택)

렉/오류 진단용 관측 스택(Grafana Cloud + Alloy 단일 에이전트)은 opt-in 으로 분리되어 있다:

```shell
docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d --build
```

- 셋업 절차·지표 분류표·진단 쿼리: [docs/OBSERVABILITY.md](docs/OBSERVABILITY.md)
- ESI 최신 스펙 대조 감사(수정 이력 + 잔여 이슈): [docs/ESI_SPEC_AUDIT.md](docs/ESI_SPEC_AUDIT.md)

## 8. 트레이드오프와 한계

*   **OS 종속성**: WPF 기반의 스탠드얼론 앱은 Windows 환경에 국한됨. 범용성보다는 타겟 유저층의 환경에서의 실행력에 집중함.
*   **신뢰 모델**: 윈도우 타이틀을 신뢰 신호로 삼으나, 실제 위치 데이터 조회를 위해서는 유효한 ESI 토큰이 필요하므로 보안 리스크는 제한적임.
*   **단일 호스트 구조**: 수평적 확장보다는 단일 노드 내에서의 고가용성과 저비용 자가 호스팅 최적화에 초점을 맞춤.

## 9. 사용 기술

*   **Languages**: C# (WPF), PHP 7.4 (FPM), JavaScript (Node.js/Workers)
*   **Infra**: Docker Compose, Traefik, Nginx, Redis, MariaDB
*   **Security**: DPoP JWT, Cloudflare KV, App Scheme, WebSocket

## 10. 참고 링크 및 라이선스

*   **원본 Pathfinder**: [exodus4d/pathfinder](https://github.com/exodus4d/pathfinder)
*   **스탠드얼론 앱**: [4cozm/GOMUL-helper](https://github.com/4cozm/GOMUL-helper)
*   **License**: MIT License - 상세 내용은 [LICENSE.md](LICENSE.md) 참고.
*   **Author**: techfreak, 4cozm (DMC Extensions)
