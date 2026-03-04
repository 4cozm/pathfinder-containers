# DMC Helper: 백엔드 버전 제어 및 WebSocket 연동 API

Pathfinder V2는 `dmc_helper` 전용 API와 WebSocket 게이트를 통해 클라이언트의 버전을 통제하고 동기화합니다.

## 1. 개요 (Overview)

- **목적**: 클라이언트의 강제 업데이트 유도 및 버전 미달 시 WebSocket 연동 차단.
- **아키텍처**: GitHub Actions 빌드 파이프라인(`deploy-gomul.yml`)에서 통보된 새 버전을 `DmcHelperController`가 수신하여 로컬 파일 및 F3 캐시에 저장합니다.
- **WebSocket 연동**: Ratchet WebSocket 서버(`MapUpdate.php`)는 F3의 `Cache` 인스턴스를 공유하여 최신 버전을 실시간으로 참조합니다.

## 2. API 명세 (API Specification)

### **버전 등록 (POST /api/DmcHelper/version)**
GitHub Actions 전용 API입니다.
- **Body**: `{"version": "1.0.x", "secret": "..."}`
- **기능**:
  - `/tmp/dmc_helper_version.txt` 파일에 기록.
  - `Cache::instance()->set('dmchelper_min_version', $version)`를 통해 WebSocket 서버 동기화.
- **보안**: `PF_DMC_HELPER_SECRET` 환경변수 또는 `DISCORD_TO_PF_HMAC` 시크릿을 통해 인증을 수행합니다.

### **최신 버전 조회 (GET /api/DmcHelper/version)**
클라이언트 `AutoUpdater` 전용 API입니다.
- **Response**: `{"ok": true, "version": "1.0.x"}`
- **기능**: 현재 등록된 최신 버전 정보를 반환하여 클라이언트 업데이트 여부를 결정하게 합니다.

## 3. WebSocket 버전 체크 로직 (MapUpdate.php)

`standalone.bind` 태스크 수신 시 다음 과정을 통해 클라이언트를 검증합니다:
1. **버전 정보 추출**: 페이로드의 `load.version` 필드를 읽습니다.
2. **캐시 대조**: `\Cache::instance()->get('dmchelper_min_version')` 값을 가져옵니다.
3. **버전 비교**: `version_compare($client, $min, '<')`가 참이면 차단합니다.
4. **차단 응답**: `ok: false, code: 'version_mismatch'`를 반환하고 즉시 `conn->close()`를 수행합니다.

## 4. 디버그 및 유지보수 가이드 (for 3.1 Pro)

- **버전 파일 위치**: 리눅스 서버 기준 `/tmp/dmc_helper_version.txt`입니다. (Docker 환경에 따라 변경될 수 있음)
- **캐시 동기화**: F3 프레임워크의 캐시 설정(Redis/File/Apcu)에 따라 WebSocket 서버와의 전파 속도가 달라질 수 있습니다. `DmcHelperController`는 항상 원자적으로 이 캐시를 갱신합니다.
- **오류 추적**: `standalone.bound` 응답의 `code` 필드를 통해 버전 불일치 여부를 확인할 수 있습니다.
