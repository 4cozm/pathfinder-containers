# 코퍼레이션 ACL 설계 (corp_acl)

> 흩어져 있던 **로그인 화이트리스트**와 **맵 수정 권한**을, 코퍼레이션 단위의 단일 ACL 테이블로 묶어 **웹에서 동적으로** 관리하기 위한 설계 문서.
> 대상: 이 포크는 **단일 맵(ID 3, "고양이 구멍", Corporation 타입)** 만 운영한다.

---

## 0. 목표 (TL;DR)

- 권한을 **corp당 두 개의 레버**로 단순화한다.
  1. **로그인 가능?** (`can_login`) — 들어올 수 있나 = (자동으로) 볼 수 있나
  2. **수정 가능?** (`can_edit`) — 보기만 vs 편집(추가/수정/삭제)
- 여기에 **만료(`expires`)** 를 더해 "이 corp은 N일간만 허용" 같은 기간제 접근을 지원한다.
- **개인 예외는 동일 형태의 `character_acl` 계층**으로 둔다 — 개인이 corp을 **완전 오버라이드**(허용·차단 둘 다). 개인 entry가 만료되면 corp 정책으로 복귀.
- 관리는 **슈퍼 어드민(SUPER)** 이 웹 `admin` 페이지에서, **매니저는 읽기 전용**.
- **SUPER 역할 지정은 `pathfinder.ini` 정적 유지**(부트스트랩 보안). corp_acl은 일반 corp만 다룬다.

---

## 1. 현행 흐름 (As-Is)

```
[EVE SSO 로그인]
   │
   ▼ isAuthorized()                         ← ini 화이트리스트 (정적)
   │   ├─ character_right 레코드 있으면 → OK (포크가 추가한 개인 우회)
   │   └─ 없으면 pathfinder.ini LOGIN.CORPORATION/CHARACTER/ALLIANCE 와 대조
   ▼ getRole()                              ← ini ROLES (정적), 기본 MEMBER
   ▼ [맵 보기] hasAccess()
   │   └─ getMaps()가 로그인한 전원에게 맵 #3 자동 부여 (하드코딩)
   ▼ [맵 수정] hasRight(char, 'map_xxx')
       └─ corporation_right 매트릭스(6액션 × 역할 level) 비교
```

### 핵심 사실 (설계 근거)

| 사실 | 위치 |
|---|---|
| 로그인 화이트리스트는 **ini 정적값** | [pathfinder.ini `[PATHFINDER.LOGIN]`](../pathfinder/app/pathfinder.ini) 87행 `CORPORATION=` |
| 화이트리스트 검사 로직 | [`CharacterModel::isAuthorized()`](../pathfinder/app/Model/Pathfinder/CharacterModel.php) 690행 |
| **로그인 = 맵 #3 보기**가 이미 하드코딩됨 (멤버십 불필요) | [`CharacterModel::getMaps()`](../pathfinder/app/Model/Pathfinder/CharacterModel.php) 1407~1423행 |
| 수정 권한 판정 | [`MapModel::hasRight()`](../pathfinder/app/Model/Pathfinder/MapModel.php) 862행 |
| 기존 코퍼 권한 매트릭스 저장 | `corporation_right` 테이블 / [`Admin::saveSettings()`](../pathfinder/app/Controller/Admin.php) 261행 |
| 기존 코퍼 권한 탭 목록은 **모든 corp**(화이트리스트 아님) | [`Admin::getAccessibleCorporations()`](../pathfinder/app/Controller/Admin.php) 685행 → `CorporationModel::getAll()` |
| SUPER/CORPORATION 역할 지정 | [pathfinder.ini `[PATHFINDER.ROLES]`](../pathfinder/app/pathfinder.ini) 377행, [`CharacterModel::getRole()`](../pathfinder/app/Model/Pathfinder/CharacterModel.php) 775행 |

### 왜 바꾸나 (문제점)

- 권한이 **3곳(ini 화이트리스트 / corp_right / 멤버십)** 에 흩어져 있고 서로 연계되지 않는다.
- 기존 corp_right 탭은 **6액션 × 멤버/매니저/어드민** 매트릭스라 과하게 복잡하고, **모든 corp**(적대 corp 포함, 로그인 실패해도 DB에 기록됨)이 목록에 떠 화이트리스트와 무관하다.
- 화이트리스트는 ini라 **빌드/재배포** 없이는 못 바꾼다.

---

## 2. 설계 (To-Be)

### 2.1 단일 테이블 `corp_acl`

```
corp_acl
──────────────────────────────────────────────────────────
corporationId   BIGINT     PK / UNIQUE   대상 코퍼레이션
can_login       BOOL       default 1     로그인 허용 여부 (소프트 차단에도 사용)
can_edit        BOOL       default 0     맵 편집(추가/수정/삭제) 허용. 기본은 "보기만"
expires         DATETIME   NULL          절대 만료 시각(UTC). NULL = 무제한
updated_by      BIGINT     NULL          마지막으로 설정한 SUPER characterId
created / updated  ...                   감사용 타임스탬프
```

- **`can_edit` 기본 0** — "추가했더니 곧바로 아무나 수정" 사고 방지. 편집은 명시적으로 켜야 한다.
- 단일맵 구조이므로 corp_acl 한 행이 곧 "그 corp의 맵 #3 권한"이다.

### 2.1b 개인 계층 `character_acl` (기존 `character_right` 대체)

```
character_acl
──────────────────────────────────────────────────────────
characterId     BIGINT     PK / UNIQUE   대상 캐릭터
can_login       BOOL                     로그인 허용/차단 (개인 단위)
can_edit        BOOL       default 0     맵 편집 허용/차단
expires         DATETIME   NULL          이 entry의 유효기한. NULL = 무기한
memo            VARCHAR    NULL          메모(본캐/소속 등) — 기존 퍼스널 탭 메모 유지
updated_by      BIGINT     NULL
created / updated  ...
```

- **corp_acl과 완전 동일한 모양** → 만료 UX·로직을 그대로 재사용(한 가지 모델).
- 기존 `character_right`(6액션 세분화 허용/차단)를 **대체**한다. 액션별 granularity는 버리고 `can_edit` 불리언으로 단순화.
- **개인이 corp을 완전 오버라이드**: entry가 존재(미만료)하면 그 값이 corp_acl보다 우선. **허용도 차단도** 가능(예: corp 허용인데 스파이 한 명만 개별 차단 / corp 보기만인데 한 명만 편집 허용).
- 만료 시 fallback: 개인 entry가 만료되면 그 줄을 무시 → corp_acl 정책으로 복귀(완전 차단 아님).

### 2.2 두 레버의 의미

| corp 상태 | can_login | can_edit | 결과 |
|---|---|---|---|
| 차단 | 0 | – | 로그인 불가 |
| 보기만 (기본) | 1 | 0 | 로그인·맵 #3 열람 가능, 편집 불가 |
| 보기 + 수정 | 1 | 1 | 편집까지 가능 |
| + 만료 | (위와 동일) | | `expires` 지나면 로그인 차단 |

> **보기는 별도 레버가 없다.** 로그인하면 맵 #3가 자동 부여되므로(1.핵심사실 참조) `can_login`이 곧 열람 권한이다. 맵 멤버십(`CorporationMapModel`)은 관리할 필요 없다.

### 2.3 Enforcement 변경 지점 · 우선순위

권한 판정은 **개인(character_acl) → 코퍼(corp_acl) → 기본 차단** 순으로 내려간다. SUPER(ini)는 항상 최우선 통과.

```
resolveLogin(character):
  if character is SUPER or CORPORATION(ini):  return 허용   # 부트스트랩 어드민/매니저 (관리 페이지 접근용)
  ce = character_acl[character]   (존재 & expires 미경과)
  if ce: return ce.can_login      # 개인 완전 오버라이드 (허용/차단)
  co = corp_acl[character.corp]   (존재 & expires 미경과)
  if co: return co.can_login
  return 차단                      # 기본 deny (session_sharing 로그인 바이패스 없음)

resolveEdit(character):           # 맵 #3
  if character is SUPER(ini):     return 허용
  ce = character_acl[character]   (존재 & 미경과)
  if ce: return ce.can_edit
  co = corp_acl[character.corp]   (존재 & 미경과)
  if co: return co.can_edit
  return 불가
```

- **`expires`는 "이 entry의 유효기간"** — 허용이든 차단이든 만료되면 그 줄을 **무시하고 다음 계층으로 fallback**. (개인 임시 허용·임시 차단이 끝나면 corp 정책으로 복귀)
- **CORPORATION(매니저)도 로그인은 ACL 무관 통과** — 읽기 전용 관리 페이지를 봐야 하므로. (편집 권한은 별개: hasRight는 SUPER만 바이패스, 매니저는 ACL을 따름)
- **session_sharing 로그인 바이패스 제거** — 모든 캐릭터는 ACL(SUPER/매니저 ini 포함)에 명시적으로 승인돼야 로그인된다. 공유 세션이어도 우회 없음. 개별 승인이 필요하면 '개인 관리'(character_acl)에 등록. (보통 다 승인받고 들어오는 운영 방식과 일치 — 그게 개인 관리의 존재 이유.)
- **SUPER 판정 소스 일원화**: `isAuthorized`·`hasRight` 모두 [`CharacterModel::isSuperAdmin()`](../pathfinder/app/Model/Pathfinder/CharacterModel.php)(=`getRole()`, ini 실시간)를 사용 → ini ROLES 변경이 즉시 반영(roleId DB 저장값의 stale 문제 없음).
- **`isExpired()` 파싱 실패 = 만료 간주(deny 방향)** — default-deny 기조와 일치.

| 함수 | 변경 |
|---|---|
| [`CharacterModel::isAuthorized()`](../pathfinder/app/Model/Pathfinder/CharacterModel.php) | ini 화이트리스트 → 위 `resolveLogin`. SUPER(ini)는 유지. |
| [`MapModel::hasRight()`](../pathfinder/app/Model/Pathfinder/MapModel.php) | 코퍼 역할-레벨 계산(`member 2 < admin 10`) → 위 `resolveEdit`(can_edit). private 맵 분기는 유지. |

- **`corporation_right` 매트릭스 탭 / [`Admin::saveSettings()`](../pathfinder/app/Controller/Admin.php) / 기존 `character_right` 액션별 구조는 제거**. 편집 권한의 단일 소스는 `*_acl.can_edit`.
- SUPER 어드민은 두 ACL과 무관하게 전부 통과(기존 동작 유지).

### 2.4 만료 강제 (lazy + cron)

- **권위 = 로그인 시 비교.** `isAuthorized()`가 `expires > now()`를 직접 확인 → 만료 corp은 그 즉시 로그인 차단. **cron이 안 돌아도 못 들어온다.**
- **cron은 보조** — 하루 1회 만료 행 정리/표시/알림용. (이 포크엔 cron 인프라 존재: `app/Cron/`, `CronModel`)

---

## 3. 만료(expiry) UX 설계

> 근본 원칙: **기간이 아니라 절대 마감일을 저장한다.** "7일"을 저장하면 "언제까지?"를 역산해야 하고, 저장 때마다 기준이 밀려 리셋 버그가 난다.

### 3.1 데이터·계산 원칙

1. **저장값은 절대 DATETIME(UTC)**, 빈값 = 무제한(NULL). 기간 문자열 저장 금지.
2. 숫자+단위는 **클라이언트 계산기**일 뿐 — 입력 즉시 `기준 ± 델타`로 **절대 마감일**을 계산해 미리보기·제출한다. 제출·저장·비교는 항상 절대값.
3. **델타 칸이 비면 만료일은 안 건드린다** → 다른 필드만 저장해도 마감일 불변(리셋 버그 차단).
4. 서버는 제출된 절대값을 **재계산하지 않고 검증만** 한다(파싱 가능 / 과거면 `now`로 클램프). → 미리보기 = 저장값(WYSIWYG).

### 3.2 입력 UI

```
만료일:  2026-06-22 14:00:00   (D-1)
조정:   [ 추가 ▼ ] [  1  ] [ 일 ▼ ]      ← 방향(추가/감소) · 숫자 · 단위(시간/일/주, 기본 일)
        ☐ 무제한으로
```

**기준점 규칙:** `기준 = (expires가 미래면 그 값, 아니면 now)`, 거기에 추가는 `+델타`, 감소는 `−델타`.

| 상황 | 추가 결과 | 감소 결과 |
|---|---|---|
| 미래 만료 | `expires + 델타` | `expires − 델타` (아직 미래면 그대로) |
| 미래 만료, 감소가 과거로 내려감 | – | **`now`로 클램프 = 즉시 만료** |
| 만료됨/과거 | `now + 델타` | 변화 없음/비활성 |
| 무제한(NULL) | `now + 델타` (무제한 종료) | **비활성**(뺄 시각 없음) |

### 3.3 저장 전 변경 요약 (diff)

저장 시 바로 커밋하지 않고, **바뀌는 항목만** before→after로 확인받는다.

```
─── 변경 사항 확인 ──────────────────────────────────
 로그인      허용 → 차단
 편집권한    보기 불가 → 보기 허용
 만료일      2026-06-22 14:00 → 2026-06-23 14:00  (1일 추가)
────────────────────────────────────────────────
                              [ 취소 ]   [ 저장 ]
```

**diff 판정 규칙(항목별):**

| 항목 | 조건 | 표시 |
|---|---|---|
| 일반 변경 | old ≠ new | `항목  old → new` |
| 만료 연장/단축 | new가 미래 | `만료일  old → new (n단위 추가/감소)` |
| **즉시 만료** | **new ≤ now** | `⚠ 만료일  old → 지금 (즉시 만료)` + `이 코퍼는 저장 즉시 로그인이 차단됩니다.` (경고색) |
| 무제한 전환 | new = NULL | `만료일  old → 무제한` |
| 변경 없음 | 줄 생략 | — |

- 즉시 만료처럼 결과가 큰 변경은 **경고색 + 평문 결과 설명**으로 강조. 저장 버튼도 `[ 즉시 만료하고 저장 ]`로 라벨 변경(선택).
- 변경이 하나도 없으면 저장 버튼 비활성.
- 구현: 폼이 원본 값(만료 절대값, can_login, can_edit)을 `data-*`로 들고 있다가 제출 직전 클라이언트에서 diff 생성.

### 3.4 상태 표시

| 저장값 | 표시 |
|---|---|
| `NULL` | 🟢 무제한 |
| 미래 | 🟡 2026-06-23까지 (D-7) |
| 오늘 | 🟠 오늘 만료 |
| 과거 | 🔴 만료됨 (N일 지남) — 로그인 차단 중 |

`updated_by` / `updated`로 **"누가 / 언제 설정했는지"** 한 줄 함께 노출.

---

## 4. 관리 UI (새 "코퍼 관리" 탭)

기존 corp_right 매트릭스 탭을 **대체**하는 단순 탭. 화이트리스트(=corp_acl)에 등록된 corp만 표시.

```
[코퍼 관리]
  ┌─────────────────────────────────────────────┐
  │ 🏢 아무개 코퍼레이션                            │
  │   로그인 허용  [✓]                              │
  │   맵 수정 허용 [ ]   (해제 = 보기만)             │
  │   만료일  2026-06-23 (D-7) 🟡                   │
  │   조정   [추가 ▼][ 1 ][일 ▼]  ☐ 무제한으로       │
  │   설정자: ㅇㅇ / 2026-06-16                     │
  │                       [저장] [제거(소프트)]      │
  └─────────────────────────────────────────────┘
  + 신규 corp 추가 (corp ID 검색 → 행 생성)
```

- **신규 corp 추가**: corp ID로 검색해 corp_acl 행 생성(기본 can_login=1, can_edit=0, expires=NULL).
- **제거**: **하드 삭제**(행 erase). A안에서는 ini 재시드가 없어 부활하지 않으므로 안전하다. "잠시 차단"은 *로그인 허용 토글 off*(행 유지)로, "완전 삭제"는 *제거*로 분리 — 두 가지를 모두 제공.
- **접근 제어**: settings/코퍼관리 페이지는 SUPER만 수정. **매니저는 읽기 전용**(목록만). 현재 [`Admin::dispatch()`](../pathfinder/app/Controller/Admin.php) 143행이 SUPER 전용 게이트이므로, 매니저용 읽기 분기를 추가.

### 4.1 개인 탭 (character_acl)

기존 "Personal Rights" 탭을 **corp 관리 탭과 동일한 형태**로 단순화한다.

- corp당 카드와 동일: **로그인 허용 / 맵 수정 허용 토글 + 만료 입력(추가/감소·숫자·단위) + 저장 전 diff + 메모**.
- 기존 **액션별 체크박스(6개) 제거** → `can_edit` 토글 하나.
- 캐릭터 ID 검색 → `character_acl` 행 생성(기존 퍼스널 탭의 검색·메모 UX 유지).
- 만료 입력 JS·diff 모달은 corp 탭과 **공용 컴포넌트**로 재사용.

---

## 5. 마이그레이션 전략 — **A안: 일회성 시드 후 ini 무시**

기존 ini 화이트리스트를 corp_acl로 **1회만** 옮기고, 이후 ini는 무시한다. DB가 유일한 진실 소스.

### 절차 (구현 반영)

> 실제 구현: 컨테이너 시작이 아니라 **`/setup` 위저드**(htpasswd 보호, 배포 후 관리자가 1회 방문)에서 모델별 `setup()`이 돌 때 시드된다. 마커는 별도 테이블 대신 **"테이블이 비어있으면 시드"**(empty-guard)로 구현 — [`CorpAclModel::seedFromConfig()`](../pathfinder/app/Model/Pathfinder/CorpAclModel.php) / [`CharacterAclModel::migrateFromLegacy()`](../pathfinder/app/Model/Pathfinder/CharacterAclModel.php).

1. `/setup` 실행 → 각 ACL 모델 `setup()`이 테이블 생성 후 시드 함수 호출. 테이블에 행이 있으면 **즉시 반환**(재시드 안 함).
2. **테이블이 비어있으면**:
   - `pathfinder.ini` `LOGIN.CORPORATION` 의 각 corp ID를 `corp_acl`에 `INSERT`(can_login=1, can_edit=0, expires=NULL).
   - 기존 **`character_right` 행 → `character_acl`로 이행**(can_login=1; can_edit는 기존 active 허용 여부를 어떻게 매핑할지 = **구현 직전 질문 다이얼로그로 결정**, 기본은 안전하게 0). 메모 보존.
   - (선택) `LOGIN.CHARACTER` 를 character_acl 시드에 포함할지 = **구현 직전 질문 다이얼로그로 결정**(기존 character_right 우회로 이미 커버될 수 있음).
   - 마커를 `1`로 설정.
3. **마커가 있으면**: 아무것도 안 한다 → **이후 ini 변경은 반영되지 않는다.**

### 결정·주의

- 멱등성: 마커 기반이라 재부팅·재실행해도 **두 번 시드되지 않음**.
- ini는 **"비상시 부트스트랩"** 으로만 문서화. 일상 관리는 웹(코퍼 관리 탭).
- A안을 택했으므로 "ini에 옛날처럼 추가하면 반영" 편의는 **포기**(웹에서만 추가). 대신 모델이 단순하고 진실 소스가 하나다.
- (B안이었다면 "INSERT-if-absent 매부팅 + 제거=소프트차단"이 필수였음 — A안에서는 불필요.)

---

## 6. 작업 항목 (구현 시)

- [ ] `CorpAclModel`(`corp_acl`) · `CharacterAclModel`(`character_acl`) 추가 — Cortex 모델, `fieldConf`, `setup()`
- [ ] 부팅 시 **일회성 시드 + 마커** 로직 (ini corp + 기존 character_right 이행)
- [ ] `isAuthorized()` → `resolveLogin`(개인→코퍼→deny, SUPER 유지)
- [ ] `hasRight()` → `resolveEdit`(개인→코퍼, can_edit), private 분기 유지
- [ ] 기존 corp_right 매트릭스 탭 / `saveSettings()` / character_right 액션별 구조 제거
- [ ] 새 "코퍼 관리" 탭 + "개인" 탭(공용 컴포넌트): 라우트, 템플릿, 신규/저장/소프트제거
- [ ] 만료 입력 JS: 추가/감소·숫자·단위 → 절대값 계산, 저장 전 diff 모달 (두 탭 공용)
- [ ] 매니저 읽기 전용 분기
- [ ] (선택) cron: 만료 행 표시/정리/알림

## 7. 확정된 결정 사항

- 맵 #3 타입: **Corporation**
- 권한 축: **can_login(+expires) / can_edit** 2개
- 계층: **2계층 ACL** — `character_acl`(개인) → `corp_acl`(코퍼) → 기본 차단, SUPER(ini) 최우선
- 개인 계층: **corp_acl과 동일 형태로 통일**(액션별 granularity 제거), **완전 오버라이드**(허용·차단 둘 다), 만료 시 corp으로 fallback
- 만료: **절대 DATETIME 저장**, 추가/감소·숫자·단위 입력, **저장 전 diff 확인**, 즉시 만료 경고
- 만료 강제: **로그인 시 비교(권위) + cron 보조**
- SUPER: **ini 정적 유지**
- 마이그레이션: **A안(일회성 시드 후 ini 무시)**
- 제거: **하드 삭제**(행 erase) + "잠시 차단"은 로그인 토글 off

## 8. ⚠ 동작 변경 (배포 시 확인 필수)

- **로그인 기본 차단(default-deny)**: 이전엔 ini 화이트리스트가 *비어있으면 전원 허용*이었으나, 이제는 ACL/SUPER에 없으면 **차단**이다. 기존 접근은 시드(ini corp + character_right + ini character)로 보존되지만, **`/setup` 후 corp_acl·character_acl이 예상대로 채워졌는지 반드시 확인**한 뒤 운영에 반영할 것(누락 시 해당 사용자 로그인 불가).
- **얼라이언스 로그인 화이트리스트(`LOGIN.ALLIANCE`) 미지원**: 2계층(corp/character)만 다룬다. 얼라 단위 허용이 필요하면 소속 corp들을 corp_acl에 등록.
- **SUPER 지정은 여전히 `pathfinder.ini [PATHFINDER.ROLES]`**: 본인이 거기 SUPER로 있어야 ACL 관리 페이지에 접근 가능(자기 잠금 방지).
