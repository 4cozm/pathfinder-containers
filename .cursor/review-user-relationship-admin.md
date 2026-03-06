# 유저 관계도 Admin 구현 리뷰

플랜 문서: `유저_관계도_admin_(mariadb·멱등·문서화)_4aba722d.plan.md`  
검토일: 2025-03-06

---

## 1. 플랜 대비 구현 일치 여부

| 항목 | 플랜 | 구현 | 일치 |
|------|------|------|------|
| dmc_helper GetOrCollect | 캐시 없으면 스캔만, 쓰기 제거 | TryWriteCache 호출 제거됨 | ✅ |
| dmc_helper WriteCache | bound 성공 시에만 호출 | AppLogic에서 ok && uids.Count>0 시 호출 | ✅ |
| pathfinder Redis 제거 | standaloneUidsPersist 제거 | 해당 호출 없음(이미 제거) | ✅ |
| MariaDB 저장 | bind 시 INSERT ON DUPLICATE KEY UPDATE | standaloneDetectPersist 구현됨 | ✅ |
| Dockerfile.websocket | pdo_mysql 추가 | docker-php-ext-install … pdo_mysql | ✅ |
| Admin spydetect | data/enrich DB·ESI, initSpydetect | dispatch 분기·메서드 구현됨 | ✅ |
| 템플릿·탭 | admin 유저 관계도 탭, spydetect.html | admin.html 탭, spydetect.html 테이블+JS | ✅ |
| 문서화 | .cursor에 계획+구현 조합 | user-relationship-admin.md 존재 | ✅ |

---

## 2. 터질 위험·엣지 케이스

### 2.1 Admin.php — DB·ESI

- **getDB()**: 부모 `Controller::getDB('PF')` 사용. DB 미설정 시 null 반환 → `spydetectData`/`spydetectEnrich`에서 500과 JSON 반환 후 exit. ✅ 적절히 처리됨.
- **spydetectData**: `$db->exec('SELECT ...')` 반환값을 `$rows ?: []`로 처리. F3 SQL의 exec는 SELECT 시 배열 반환. null 가능성은 런타임/버전에 따라 다를 수 있으므로, `$rows = $db->exec(...);` 직후 `$rows = is_array($rows) ? $rows : [];` 로 정규화하면 더 안전함.
- **spydetectEnrich**: `getCharacterData()` 예외는 try/catch로 500 반환. ✅  
  ESI가 캐릭터를 못 찾는 경우: `$charData->character`가 비어있을 수 있음. 현재 `isset($charData->character['name']) ? ... : ''` 로 방어됨. ✅  
  `$charData->corporation` null 체크 후 `_id`, `name` 사용. ✅
- **saveSettings (기존 코드)**: `(int)$corporation->id === $corporationId` 사용. ✅ (선택 영역에 `_id`로 되어 있었다면 타입/필드 불일치로 매칭 실패할 수 있으므로, 반드시 `id` + `(int)` 캐스팅 유지 권장.)

### 2.2 MapUpdate.php — 웹소켓·MariaDB

- **payload 구조**: `$data = (array)$payload->load`, `$uids = $data['uids']`. dmc_helper의 `SendBindAsync`가 `load["uids"] = uids` 로 보내므로 키 일치. ✅
- **standaloneDetectPersist**:
  - `MYSQL_HOST`/`MYSQL_PF_DB_NAME` 비어 있으면 조기 return. ✅
  - `MYSQL_USER`/`MYSQL_PASSWORD` 없으면 `(string)$user`/`(string)$pass`로 빈 문자열 전달 → 연결 실패 시 catch에서 error_log만 하고 종료. 워크소켓 프로세스는 안 죽음. ✅
  - uid 검증: `is_scalar`, `ctype_digit` 후 `(int)` 로 정수만 사용. ✅
  - PDO 예외 시 error_log 후 return. ✅
- **실무 권장**: `MYSQL_USER`가 비어 있으면 PDO 연결 시도 자체를 하지 않고 return 하면, 잘못된 환경에서의 불필요한 실패 로그를 줄일 수 있음.

### 2.3 dmc_helper — 멱등 캐시

- **GetOrCollect**: 캐시 없을 때 스캔만 하고 반환, 쓰기 없음. ✅
- **WriteCache**: null/Count==0 일 때 return. ✅
- **AppLogic**: `type == "standalone.bound"` && `ok` && `uids.Count > 0` 일 때만 WriteCache. 수신 루프에서 사용하는 `uids`는 연결 직후 `GetOrCollect()`로 얻어 `SendBindAsync(..., uids)`에 넘긴 그 목록이므로, 클로저로 캡처된 `uids`와 일치. ✅
- **StandaloneUidCache.cs**: `Path`, `File`, `Directory` 사용. 프로젝트에 `ImplicitUsings` 또는 `using System.IO` 없으면 컴파일 오류. 전역 usings 확인 권장.

---

## 3. 다른 워크스페이스와의 교류

### 3.1 dmc_helper ↔ pathfinder (웹소켓)

- **프로토콜**:  
  - 클라이언트: `StandaloneWs.SendBindAsync(ws, ticket, jwk, uids)` → `load["uids"]` 배열 전송.  
  - 서버: `standalone.bind` 시 `$data['uids']` 수신 후 `standaloneDetectPersist($uids)`.  
  타입은 문자열 배열/리스트로 일치. ✅
- **bound 응답**: 서버가 `standalone.bound` (ok: true) 보낸 뒤, 클라이언트가 수신하면 WriteCache 호출. 순서 일치. ✅

### 3.2 pathfinder (PHP) ↔ DB

- **pathfinder 앱**: Admin의 `getDB()` → F3 `PF` DB. `standalone_detect_characters` 테이블이 같은 pathfinder DB에 있음. ✅
- **웹소켓 컨테이너**: MapUpdate는 F3가 아닌 **환경변수 기반 PDO**로 직접 연결. 호스트/DB명은 `templateEnvironment.ini` 등과 동일한 `MYSQL_*` 사용 필요. docker-compose에서 pf-socket은 `env_file: .env` 사용. ✅  
  **배포 시**: `.env`에 `MYSQL_HOST`, `MYSQL_PF_DB_NAME`, `MYSQL_USER`, `MYSQL_PASSWORD`(, `MYSQL_PORT`)가 웹소켓에도 전달되는지 반드시 확인할 것.

### 3.3 스키마

- **standalone_detect_characters.sql**: PK `character_id`, 컬럼명·타입이 Admin/MapUpdate 사용처와 일치. ✅
- **마이그레이션**: `docker-compose`의 `pf-migrate-standalone` 서비스가 배포 시 DDL을 자동 실행함. 수동 체크리스트 불필요.

---

## 4. 보안·안정성

### 4.1 XSS (중요)

- **spydetect.html**: 목록 렌더 시 `c.character_id`, `c.name`, `c.corporation_name`, `c.updated_at`를 **innerHTML**로 삽입.
- `name`/`corporation_name`은 ESI/DB 기원이라 `<script>`, `"onerror=..."` 등이 들어갈 수 있음. **이대로면 XSS 가능.**
- **권장**: 테이블 셀에는 **textContent** 사용하거나, HTML 이스케이프 함수를 적용한 뒤 innerHTML 사용.  
  예: `function esc(s){ var d=document.createElement('div'); d.textContent=s; return d.innerHTML; }`  
  또는 `c.name` 대신 `(c.name || '—').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/"/g,'&quot;')` 등.

### 4.2 권한

- `/admin/spydetect/*` 는 `beforeroute` → `getAdminCharacter` 통과 후에만 `dispatch`에 진입. 비로그인·비관리자 접근 차단됨. ✅
- `spydetectData`/`spydetectEnrich`는 추가로 역할(SUPER/CORPORATION) 구분 없이 “admin이면 전체 목록/전체 보강” 가능. 플랜이 “admin에서 조회·ESI 보강”이므로 현재 구현으로 수용 가능. 필요 시 “SUPER만 목록 열람” 등으로 제한 가능.

### 4.3 Enrich의 GET 부작용

- `GET /admin/spydetect/enrich/{id}` 가 DB·ESI 갱신이라는 부작용을 가짐.  
  CSRF 관점: GET이므로 링크 클릭/이미지 로드로도 호출 가능. 같은 오리진의 admin 페이지에서만 버튼으로 호출한다면 위험은 제한적이지만, **향후에는 POST + CSRF 토큰**으로 바꾸는 것이 더 안전함.

---

## 5. 정리

- **플랜 대비**: dmc_helper 멱등 캐시, pathfinder Redis 제거·MariaDB 저장, Admin 탭/API, Dockerfile, 문서화까지 계획과 일치하게 구현되어 있음.
- **터질 위험**: DB null/배열 정규화, 웹소켓 쪽 DB 미설정 시 조기 return, C# 쪽 System.IO 사용 가능 여부만 점검하면 됨.
- **워크스페이스 연동**: dmc_helper–웹소켓 bind/uids·bound 응답, pathfinder–MariaDB(앱·웹소켓) 사용처와 스키마가 맞고, 배포 시 `.env`·DDL 실행만 확인하면 됨.
- **필수 수정 권장**: **spydetect.html 목록 렌더 시 name/corporation_name HTML 이스케이프 또는 textContent 사용**으로 XSS 제거.
- **선택 개선**: spydetectData의 exec 반환 배열 정규화, standaloneDetectPersist에서 MYSQL_USER 비어 있으면 연결 시도 생략, enrich를 POST+CSRF로 전환 검토.
