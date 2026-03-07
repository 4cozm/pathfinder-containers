# DMC Helper 버전 API E2E 흐름 검증 (GitHub Action 정상 인증 기준)

GitHub Action이 올바른 `secret`과 `version`을 POST했을 때의 코드 흐름을 역추적한 검증 문서.

---

## 1. GitHub Action → POST /api/DmcHelper/version

### 1.1 라우팅

- **파일**: `pathfinder/app/routes.ini`
- **라인 19**: `POST /api/DmcHelper/version = ... \Controller\Api\DmcHelper->version, 0, 512`
- F3가 `POST` 메서드와 경로가 일치하면 `DmcHelper->version(Base $f3)` 호출.  
- 와일드카드 `GET|POST /api/@controller/@action`(라인 23)보다 **위에** 정의되어 있어 이 경로가 우선 매칭됨.

### 1.2 DmcHelper->version() (Pathfinder)

- **파일**: `pathfinder/app/Controller/Api/DmcHelper.php`

| 단계 | 코드 위치 | 동작 |
|------|-----------|------|
| Body 파싱 | `readJsonBody()` | `php://input` JSON → `['version' => 'x.y.z', 'secret' => '...']` |
| version 검증 | L36-39 | `version` 비어 있으면 400 + `Missing version` |
| 시크릿 조회 | L40-46 | `Config::getEnvironmentData('PF_DMC_HELPER_SECRET')` → 없으면 `DISCORD_TO_PF_HMAC`. **출처**: F3 hive `ENVIRONMENT.*`(environment.ini) 또는 `getenv()` (docker `.env`). |
| 시크릿 검증 | L46-47 | `strlen($expectSecret) >= 8` 이고 `hash_equals($expectSecret, $secret)` 이어야 통과. 아니면 401 `Invalid secret`. |
| 파일 기록 | L49-50 | `/tmp/dmc_helper_version.txt` 에 `version\n` 기록 (pf 컨테이너 내부 경로). |
| Cache(Redis) 기록 | L52-60 | `\Cache::instance()->set('dmchelper_min_version', $version, 0)`. F3 CACHE 백엔드가 Redis일 때 동일 Redis에 키 `dmchelper_min_version` 저장. |
| 응답 | L62 | 200 + `{ ok: true, version: $version }`. |

**검증 포인트**

- Action에서 보내는 `secret` 값은 **서버 .env의 `PF_DMC_HELPER_SECRET`**(또는 없을 때 `DISCORD_TO_PF_HMAC`)과 **완전 일치**해야 함.
- Pathfinder 컨테이너는 `config.ini`의 `CACHE = redis=${REDIS_HOST}:${REDIS_PORT}` 로 Redis를 쓰므로, `REDIS_*`는 `.env` 또는 environment.ini에서 채워져 있어야 함.

---

## 2. 클라이언트(앱) → GET /api/DmcHelper/version

### 2.1 라우팅

- **routes.ini 라인 20**: `GET /api/DmcHelper/version = ... DmcHelper->getVersion, 0, 512`
- GET 요청 시 `DmcHelper->getVersion(Base $f3)` 호출.

### 2.2 DmcHelper->getVersion()

| 단계 | 코드 위치 | 동작 |
|------|-----------|------|
| 읽기 순서 | `readVersion()` | 1) `/tmp/dmc_helper_version.txt` 내용, 2) `\Cache::instance()->get('dmchelper_min_version')`, 3) 없으면 `'0.0.0'`. |
| 응답 | L24-25 | 200 + `{ ok: true, version: $version }`. |

- POST로 버전을 넣은 뒤 GET이면, 파일 또는 Cache에서 방금 넣은 버전이 나와야 함.

---

## 3. dmc_helper 클라이언트 (앱 기동 시)

### 3.1 AutoUpdater.CheckAndUpdateAsync()

- **파일**: `dmc_helper/Core/AutoUpdater.cs`
- **진입**: `App.OnStartup` → `await AutoUpdater.CheckAndUpdateAsync()` (MainWindow 표시 전).

| 단계 | 코드 | 동작 |
|------|------|------|
| 버전 API | `GetRemoteVersionAsync()` | `GET VersionApiUrl` (= `https://path-v2.../api/DmcHelper/version`) |
| 파싱 | L99-104 | 응답 JSON에서 `version` 프로퍼티 추출. |
| 비교 | L36-39 | `remoteVersion`이 비었거나 `currentVersion`과 같으면 업데이트 없음. 다르면 패치 다운로드·적용·재시작. |

- 서버가 POST로 등록한 버전과 GET 응답의 `version`이 같으므로, Action이 올바르게 등록했다면 클라이언트는 같은 버전 문자열을 받음.

---

## 4. WebSocket standalone.bind 시 버전 검사 (pf-socket)

### 4.1 클라이언트 → 서버

- **파일**: `dmc_helper/Net/StandaloneWs.cs`  
- `SendBindAsync(ws, ticket, jwk, uids)` 시 `load.version` = `Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "1.0.0"` (라인 35).

### 4.2 pf-socket MapUpdate.php

- **파일**: `websocket/app/Component/MapUpdate.php`
- **case 'standalone.bind'**: `load.version` 추출 후 `getDmchelperMinVersion()` 과 비교.

| 단계 | 코드 | 동작 |
|------|------|------|
| 최소 버전 조회 | `getDmchelperMinVersion()` | 1) env `DMCHELPER_MIN_VERSION`, 2) Redis `GET dmchelper_min_version`. (F3가 serialize한 값은 정규식으로 해석.) |
| Redis 연결 | `getRedisClient()` | `getenv('REDIS_DSN')` → Predis로 같은 Redis 접속. docker-compose에서 pf-socket도 `.env` 사용 시 `REDIS_DSN` 공유. |
| 비교 | L267-276 | `version_compare($clientVersion, $minVersion, '<')` 이면 401 + `version_mismatch` + `$conn->close()`. |

**검증 포인트**

- Pathfinder가 `Cache::instance()->set('dmchelper_min_version', $version)` 로 넣은 키와, pf-socket의 `DMCHELPER_MIN_VERSION_REDIS_KEY = 'dmchelper_min_version'` 이 **동일 키**.
- F3 Redis 캐시 백엔드가 키에 prefix를 붙이면(예: `pathfinder:dmchelper_min_version`), pf-socket에서는 해당 키로 조회해야 함. 현재 코드는 prefix 없음을 전제로 함. **실제 Redis에 저장된 키 확인 권장**: `redis-cli GET dmchelper_min_version` 또는 `KEYS *dmchelper*`.

---

## 5. E2E 요약 체크리스트 (Action 정상 인증 시)

| # | 단계 | 기대 결과 |
|---|------|-----------|
| 1 | Action → POST /api/DmcHelper/version `{ "version": "1.0.x", "secret": "<PF_DMC_HELPER_SECRET 또는 DISCORD_TO_PF_HMAC>" }` | 200, `{ ok: true, version: "1.0.x" }`. `/tmp/dmc_helper_version.txt` 및 Redis `dmchelper_min_version` 갱신. |
| 2 | 브라우저/클라이언트 → GET /api/DmcHelper/version | 200, `{ ok: true, version: "1.0.x" }` (방금 POST한 값과 동일). |
| 3 | dmc_helper 앱 기동 → AutoUpdater GET 동일 URL | 서버 버전 수신. 현재 버전과 다르면 패치 적용·재시작. |
| 4 | dmc_helper WS 연결 → standalone.bind `load.version` | pf-socket이 Redis에서 `dmchelper_min_version` 조회 후 `version_compare`; 최소 버전 미달 시만 `version_mismatch` + 연결 종료. |

---

## 6. 환경 변수 정리 (올바른 동작을 위해 필요)

| 변수 | 사용처 | 용도 |
|------|--------|------|
| `PF_DMC_HELPER_SECRET` | Pathfinder (DmcHelper->version) | POST /api/DmcHelper/version Body의 `secret`과 일치해야 200. (없으면 `DISCORD_TO_PF_HMAC` 사용.) |
| `DISCORD_TO_PF_HMAC` | Pathfinder (DmcHelper->version) | `PF_DMC_HELPER_SECRET` 없을 때 대체 시크릿. |
| `REDIS_HOST`, `REDIS_PORT` (또는 CACHE DSN) | Pathfinder config.ini | F3 Cache 백엔드 = Redis. 버전 저장소. |
| `REDIS_DSN` | pf-socket (MapUpdate getRedisClient) | 동일 Redis 접속. GET dmchelper_min_version. |
| `DMCHELPER_MIN_VERSION` | pf-socket (선택) | 설정 시 Redis 대신 이 값을 최소 버전으로 사용. |

GitHub Action에서는 **서버와 동일한 시크릿 값**을 Body의 `secret`으로 보내면, 위 E2E가 정상 동작한다.
