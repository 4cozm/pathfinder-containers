# 유저 관계도 Admin 기능 — 계획 및 구현 요약

이 문서는 유저 관계도(Admin 조회) 기능의 계획과 구현 내용을 정리한 것이다.

---

## 1. 목적

- **유저 관계도**: dmc_helper가 bind 시 **로그 폴더**(Chatlogs)에서 수집한 캐릭터 ID를 pathfinder에 저장하고, admin 화면에서 **티켓 발급 계정별**로 조회·보강할 수 있게 한다.
- 데이터 소스는 **현재 열린 윈도우**가 아니라 **로그 폴더에 등장한 캐릭터**(함대/채팅 로그 파일명에 포함된 cid)이다.
- 저장소는 **Redis 대신 기존 MariaDB**(pathfinder DB)를 사용한다.
- dmc_helper 쪽 UID 캐시는 **bind 전송 성공 시에만** 저장하도록 하여 멱등 동작을 보장한다.
- **발급 계정(issuer)** 정보를 저장하여 “누구의 티켓에서 발견된 목록인지”를 Admin에서 토글로 확인할 수 있다.

---

## 2. dmc_helper 변경 (멱등 캐시·MapId)

### 멱등 캐시

- **StandaloneUidCache.cs**
  - `GetOrCollect()`: 캐시 파일이 있으면 읽어서 반환. 없으면 Chatlogs 스캔 후 uids만 반환하고 **캐시에 쓰지 않음**.
  - public 메서드 `WriteCache(IReadOnlyList<string> uids)` 추가. bind **성공** 후에만 호출.
- **AppLogic.cs**
  - 수신 루프에서 `type == "standalone.bound"` 이고 `ok == true` 일 때, `uids.Count > 0` 이면 `StandaloneUidCache.WriteCache(uids)` 호출.

### MapId (다클라 헬퍼 맵 갱신)

- **Config/AppConfig.cs**: 하트비트/맵 갱신에 사용하는 Pathfinder 맵 ID.
  - 환경변수 `DMC_HELPER_MAP_ID`로 지정 가능. **미설정 시 기본값 3.**

---

## 3. pathfinder: 유저 관계도 저장 (MariaDB)

### DB 스키마

- **DB**: 기존 pathfinder가 사용하는 MariaDB (`MYSQL_PF_DB_NAME=pathfinder`).

- **테이블 1: `standalone_detect_characters`** (발견된 캐릭터별 name/corp 보강용)
  - `character_id` INT UNSIGNED PK
  - `name` VARCHAR(255) NULL
  - `corporation_id` INT UNSIGNED NULL
  - `corporation_name` VARCHAR(255) NULL
  - `updated_at` DATETIME

- **테이블 2: `standalone_detect_log`** (발급 계정 ↔ 발견 캐릭터 관계)
  - `issuer_character_id` INT UNSIGNED NOT NULL — 티켓 발급한 캐릭터 ID (맵에서 “다클라 헬퍼” 누른 계정)
  - `detected_character_id` INT UNSIGNED NOT NULL — bind 시 load.uids에서 수집된 캐릭터 ID
  - `updated_at` DATETIME
  - PK: `(issuer_character_id, detected_character_id)`, 인덱스: `issuer_character_id`

- **DDL·마이그레이션**
  - `pathfinder/export/sql/standalone_detect_characters.sql`, `pathfinder/export/sql/standalone_detect_log.sql`
  - **자동화**: `docker-compose up` 시 `pf-migrate-standalone` 서비스가 DB 준비 후 위 두 DDL을 순서대로 1회 실행함 (CREATE TABLE IF NOT EXISTS라 재실행해도 무방).
  - 수동 실행: `mysql -h ... -u ... -p pathfinder < pathfinder/export/sql/standalone_detect_characters.sql` 후 동일하게 `standalone_detect_log.sql` 실행.

### 웹소켓 (bind 시 MariaDB 저장)

- **Dockerfile.websocket**: PHP 확장 `pdo_mysql` 추가.
- **MapUpdate.php**
  - **기존**: `load.uids` 있을 때 Redis 저장.
  - **변경**: Redis 저장 제거. **MariaDB**에만 저장.
  - `standaloneDetectPersist(int $issuerCid, array $uids)`:
    - 티켓 검증 결과 `$cid`(발급 계정)와 `load.uids`(발견된 캐릭터 ID 목록)를 받음.
    - `standalone_detect_characters`: 각 uid에 대해 `INSERT ... ON DUPLICATE KEY UPDATE updated_at = NOW()` (name/corp 덮어쓰지 않음).
    - `standalone_detect_log`: 각 uid에 대해 `(issuer_character_id, detected_character_id)` INSERT, `ON DUPLICATE KEY UPDATE updated_at = NOW()`.
  - DB 연결: 환경변수 `MYSQL_HOST`, `MYSQL_PF_DB_NAME`, `MYSQL_USER`, `MYSQL_PASSWORD`(, `MYSQL_PORT`) 사용.

---

## 4. Admin: 유저 관계도 탭·API (발급 계정별 토글)

### 라우팅·뷰

- **admin.html**: 네비에 “유저 관계도” 탭. `tplPage == 'spydetect'`, 링크 `/admin/spydetect`.
- **admin/spydetect.html**: 발급 계정 목록(이름 + N개) + **토글** 시 해당 계정에서 발견된 캐릭터 목록을 로드해 테이블로 표시. 캐릭터별 “조회” 버튼으로 ESI 보강(enrich).

### API

- **GET /admin/spydetect/data**  
  `standalone_detect_log`에서 발급자별 건수 조회. pathfinder `character` 테이블로 발급자 이름 조회 후 반환.  
  응답: `{ "ok": true, "issuers": [ { "issuer_character_id", "issuer_name?", "detected_count" } ] }`.

- **GET /admin/spydetect/issuer/{issuer_character_id}/characters** (신규)  
  해당 발급자에서 발견된 캐릭터 목록. `standalone_detect_log` JOIN `standalone_detect_characters`.  
  발급자 이름은 pathfinder `character` 또는 `Sso::getCharacterData`(ESI)로 조회.  
  응답: `{ "ok": true, "issuer_character_id", "issuer_name?", "characters": [ { character_id, name, corporation_name, updated_at, ... } ] }`.

- **GET /admin/spydetect/enrich/{character_id}**  
  해당 행(발견된 캐릭터) 조회. name/corporation_name 이 이미 있으면 그대로 JSON 반환.  
  비어 있으면 `Sso::getCharacterData($characterId)` 로 ESI 조회 후 `standalone_detect_characters` UPDATE, 갱신된 행 JSON 반환.

### 구현 위치

- **Admin.php**: `dispatch()` 에 `case 'spydetect'` 분기.
  - `spydetect/data` → `spydetectData($f3)` (issuers JSON 후 exit).
  - `spydetect/issuer/{id}/characters` → `spydetectIssuerCharacters($f3, $id)` (JSON 후 exit).
  - `spydetect/enrich/{id}` → `spydetectEnrich($f3, $id)` (JSON 후 exit).
  - 그 외 → `initSpydetect($f3)` 후 일반 뷰 렌더.

---

## 5. 파일 변경 목록

| 구분 | 파일 | 변경 내용 |
|------|------|-----------|
| dmc_helper | Eve/StandaloneUidCache.cs | GetOrCollect()에서 캐시 쓰기 제거; WriteCache(uids) 추가. |
| dmc_helper | Core/AppLogic.cs | standalone.bound (ok) 수신 시 WriteCache(uids) 호출. |
| dmc_helper | Config/AppConfig.cs | MapId 환경변수 DMC_HELPER_MAP_ID, 기본값 3. |
| pathfinder-containers | Dockerfile.websocket | pdo_mysql 확장 추가. |
| pathfinder-containers | websocket/app/Component/MapUpdate.php | bind 시 standaloneDetectPersist($cid, $uids); standalone_detect_characters + standalone_detect_log 저장. |
| pathfinder-containers | pathfinder/export/sql/standalone_detect_characters.sql | DDL. |
| pathfinder-containers | pathfinder/export/sql/standalone_detect_log.sql | DDL (발급자–발견 캐릭터 관계). |
| pathfinder-containers | scripts/migrate-standalone-detect.sh | 두 DDL 파일 순차 실행. |
| pathfinder-containers | docker-compose.yml | pf-migrate-standalone에 standalone_detect_log.sql 마운트 추가. |
| pathfinder-containers | pathfinder/app/Controller/Admin.php | spydetect 분기, spydetectData(issuers), spydetectIssuerCharacters, spydetectEnrich. |
| pathfinder-containers | pathfinder/public/templates/view/admin.html | 유저 관계도 탭 추가. |
| pathfinder-containers | pathfinder/public/templates/admin/spydetect.html | 발급 계정 목록 + 토글 시 해당 계정 캐릭터 목록 요청/표시. |

---

## 6. 데이터 흐름 요약

1. dmc_helper: Chatlogs 스캔 또는 캐시에서 uids 수집 → **standalone.bind** 전송(ticket, jwk, uids) → **standalone.bound (ok)** 수신 시에만 `WriteCache(uids)` 호출.
2. pathfinder 웹소켓: **standalone.bind** 수신 시 티켓에서 발급자 `cid` 확보. `load.uids` 가 있으면 `standaloneDetectPersist($cid, $uids)` 호출 → MariaDB `standalone_detect_characters` 에 각 uid INSERT/UPDATE(updated_at만 갱신) + `standalone_detect_log` 에 (issuer_character_id, detected_character_id) INSERT/UPDATE.
3. Admin: 유저 관계도 탭에서 JS가 `/admin/spydetect/data` 로 **발급 계정 목록**(이름 + 건수) 조회 → “이름 (N개)” 형태로 표시. 사용자가 행 클릭 시 토글 → `/admin/spydetect/issuer/{id}/characters` 로 해당 발급자에서 발견된 캐릭터 목록 로드 → 테이블 렌더. “조회” 클릭 시 `/admin/spydetect/enrich/{character_id}` 호출 → ESI로 name/corp 조회 후 DB 갱신 및 JSON 반환 → 해당 행만 갱신.
