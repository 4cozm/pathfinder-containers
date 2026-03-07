# DMC Helper: 백엔드 버전 제어 및 WebSocket 연동 API

Pathfinder V2는 `dmc_helper` 전용 API와 WebSocket 게이트를 통해 클라이언트의 버전을 통제하고 동기화합니다.

## 1. 개요 (Overview)

- **목적**: 클라이언트의 강제 업데이트 유도 및 버전 미달 시 WebSocket 연동 차단.
- **아키텍처**: GitHub Actions 빌드 파이프라인(`deploy-gomul.yml`)에서 통보된 새 버전을 `DmcHelperController`가 수신하여 로컬 파일 및 F3 캐시에 저장합니다.
- **단일 소스(Redis)**: Pathfinder는 `Cache::instance()->set('dmchelper_min_version', $version)`로 Redis에 기록하고, WebSocket 서버(pf-socket)는 **동일 Redis**에서 키 `dmchelper_min_version`을 직접 조회합니다. pf-socket은 F3를 사용하지 않으므로 Redis를 단일 소스로 사용합니다.

## 2. API 명세 (API Specification)

### **버전 등록 (POST /api/DmcHelper/version)**
GitHub Actions 전용 API입니다.
- **Body**: `{"version": "1.0.x", "secret": "..."}`
- **기능**:
  - `/tmp/dmc_helper_version.txt` 파일에 기록.
  - `Cache::instance()->set('dmchelper_min_version', $version)`로 Redis에 기록(Pathfinder CACHE 백엔드). WebSocket은 같은 Redis 키 `dmchelper_min_version`을 읽어 동기화.
- **보안**: `PF_DMC_HELPER_SECRET` 환경변수 또는 `DISCORD_TO_PF_HMAC` 시크릿을 통해 인증을 수행합니다.

### **최신 버전 조회 (GET /api/DmcHelper/version)**
클라이언트 `AutoUpdater` 전용 API입니다.
- **Response**: `{"ok": true, "version": "1.0.x"}`
- **기능**: 현재 등록된 최신 버전 정보를 반환하여 클라이언트 업데이트 여부를 결정하게 합니다.

## 3. WebSocket 버전 체크 로직 (MapUpdate.php)

`standalone.bind` 태스크 수신 시 다음 과정을 통해 클라이언트를 검증합니다:
1. **버전 정보 추출**: 페이로드의 `load.version` 필드를 읽습니다.
2. **최소 버전 조회**: `getDmchelperMinVersion()` — env `DMCHELPER_MIN_VERSION` 우선, 없으면 **Redis 키 `dmchelper_min_version`** 조회(Pathfinder CACHE와 동일 Redis). F3가 serialize한 값도 해석.
3. **버전 비교**: `version_compare($client, $min, '<')`가 참이면 차단합니다.
4. **차단 응답**: `ok: false, code: 'version_mismatch'`를 반환하고 즉시 `conn->close()`를 수행합니다.

## 4. 디버그 및 유지보수 가이드 (for 3.1 Pro)

- **버전 파일 위치**: 리눅스 서버 기준 `/tmp/dmc_helper_version.txt`입니다. (Docker 환경에 따라 변경될 수 있음)
- **단일 소스(Redis)**: Pathfinder CACHE가 Redis일 때만 WebSocket과 동기화됩니다. Pathfinder가 `Cache::set('dmchelper_min_version', …)`를 호출하면 Redis에 기록되며, pf-socket은 `REDIS_DSN`으로 같은 Redis에서 해당 키를 읽습니다. 오버라이드가 필요하면 pf-socket에 env `DMCHELPER_MIN_VERSION`을 설정하면 됩니다.
- **오류 추적**: `standalone.bound` 응답의 `code` 필드를 통해 버전 불일치 여부를 확인할 수 있습니다.
