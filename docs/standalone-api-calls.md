# 다클라 헬퍼 토큰 관련 API 정리

직접 확인하실 때 참고용입니다.

---

## 1. 토큰(payload)을 **받아오는** 쪽 (웹)

| 항목 | 내용 |
|------|------|
| **호출 주체** | 브라우저 (Pathfinder 맵 페이지) |
| **코드 위치** | `pathfinder/public/js/standalone-hook.js` → `issueToken()` |
| **로드되는 페이지** | `public/templates/view/index.html` 에서 스크립트 로드 → **맵 등 공통 레이아웃 페이지** |
| **API** | **POST `/api/Standalone/issue`** |
| **URL (상대)** | `"/api/Standalone/issue"` → 현재 사이트 기준 (예: `https://cat4u.shop/api/Standalone/issue`) |
| **요청** | Body 없음. `credentials: "same-origin"` (쿠키/세션으로 로그인된 캐릭터 사용) |
| **헤더** | `X-Requested-With: XMLHttpRequest`, `Accept: application/json` |
| **성공 응답** | `{ "ok": true, "payload": "<base64url>", "ttl": 30 }` |
| **실패 시** | `r.ok` false 또는 `!j.payload` 이면 `null` 반환 (콘솔에 별도 로그 없음) |

**라우팅**: `pathfinder/app/routes.ini`  
- `POST /api/Standalone/issue` 는 **명시 라우트 없음**.  
- `GET|POST /api/@controller/@action` 와일드카드로 **POST /api/Standalone/issue** → `Standalone->issue` 로 처리됩니다.

**서버 처리**: `pathfinder/app/Controller/Api/Standalone.php` → `issue()`  
- 로그인된 캐릭터 필요. 없으면 401.  
- `PF_STANDALONE_SECRET` 환경변수 필요 (16자 이상). 없으면 500.  
- **시크릿은 루트 `.env` 한 곳에서만 관리** (Pathfinder Config는 hive 후 `getenv()` 폴백). `environment.ini`에는 넣지 않음.

**티켓 검증 (WebSocket)**  
- verify에서 내려준 ticket은 **서명만** 사용 (파일 미사용).  
- **pf-socket(웹소켓) 컨테이너에도 `PF_STANDALONE_SECRET`이 pf와 동일한 값으로 설정돼 있어야** bind 시 ticket 검증이 성공함.  
- `.env`에 넣고 `env_file: .env`로 두면 pf와 pf-socket 둘 다 적용됨.  
- bind 실패 시 코드: `ticket_secret_not_configured`(시크릿 없음/짧음), `ticket_signature_invalid`(시크릿 불일치), `ticket_expired`, `ticket_already_used`.

**`ticket_secret_not_configured` 나올 때**  
1. 프로젝트 루트 `.env`에 `PF_STANDALONE_SECRET=...` (16자 이상) 있는지 확인.  
2. 있으면 **pf-socket만 재기동**해서 환경변수 다시 읽기:  
   `docker-compose up -d pf-socket`  
   (또는 `docker-compose down` 후 `docker-compose up -d`로 전체 재기동.)  
3. 컨테이너 안에서 확인:  
   `docker exec pf-socket env | findstr PF_STANDALONE`

---

## 2. payload를 **쓰는** 쪽 (앱)

| 항목 | 내용 |
|------|------|
| **payload 획득** | 웹에서 받은 payload를 `pathfinder://standalone?payload=xxx` 로 앱에 전달 (앱은 **issue 호출 안 함**) |
| **앱이 호출하는 API** | **POST `/api/Standalone/verify`** |
| **URL (dmc_helper)** | `AppConfig.VerifyUrl` = `https://cat4u.shop/api/Standalone/verify` |
| **요청 Body** | `{ "payload": "<base64url>", "jwk": { ... } }` |
| **성공 응답** | ticket, ttl, cid, ts, ping_access_token 등 |

**라우팅**: `pathfinder/app/routes.ini` 18행  
`POST /api/Standalone/verify` 명시 등록 → `Standalone->verify`

---

## 3. 직접 확인하는 방법

**1) 브라우저에서 payload 받아오기 (issue)**  
- Pathfinder 맵 페이지에 **로그인**한 상태에서  
- F12 → Network 탭  
- 필터: XHR 또는 Fetch  
- **POST** `https://cat4u.shop/api/Standalone/issue` (또는 사용 중인 도메인) 확인  
- 페이지 로드 직후 prefetch로 1번, 다클라 헬퍼 링크 클릭 시 1번 더 호출될 수 있음  

**2) 실패 시 확인할 것**  
- **401**: 로그인 안 됨 → 맵 페이지에서 로그인 후 다시 시도  
- **404**: 라우팅/배포 문제 → 서버의 `routes.ini` 및 와일드카드 적용 여부 확인  
- **500**: 서버 에러 → `PF_STANDALONE_SECRET` 설정, PHP 에러 로그 확인  
- **200인데 payload 없음**: 응답 JSON에 `ok: false` 또는 `message` 확인  

**3) 콘솔 로그**  
- `standalone-hook.js` 상단: `[다클라 헬퍼] standalone-hook.js 로드됨` → 스크립트는 로드됨  
- 클릭 시: `[다클라 헬퍼] 앱 스킴 호출` + `hasPayload: true/false` → payload 유무 확인  

---

## 4. 요약

| 단계 | API | 호출하는 쪽 |
|------|-----|-------------|
| 토큰(payload) **발급** | **POST /api/Standalone/issue** | **웹 (standalone-hook.js)** |
| payload로 ticket **발급** | POST /api/Standalone/verify | 앱 (dmc_helper) |
| 핑 토큰 재발급 | POST /api/Ping/token | 앱 (dmc_helper) |

**“토큰 받아오는 코드가 안 된다”**면 → 웹에서 **POST /api/Standalone/issue** 가 실패하는지 먼저 확인하면 됩니다.

---

## 5. 빌드 후 Docker 컨테이너에 산출물 반영 확인

API가 호출되지 않으면 **빌드 산출물이 이미지/컨테이너에 제대로 들어가지 않았을 수** 있습니다.

### 5.1 빌드 순서 (필수)

1. **반드시 `pws.ps1` 먼저 실행** (gulp로 `public/js/v2.2.4`, `public/css/v2.2.4` 생성)
2. 그 다음 `pws.ps1 -Docker` 또는 `docker-compose up --build -d`  
   - 루트 `Dockerfile`이 **호스트의 `./pathfinder/`** 를 COPY하므로, gulp를 건너뛰면 `v2.2.4` 없어서 빌드 실패하거나 예전 파일이 들어감.

### 5.2 pws.ps1에서 하는 검증

- **gulp 직후**: `standalone-hook.js`, `public/js/v2.2.4`, `public/css/v2.2.4`, `public/templates/view/index.html`, `app/routes.ini` 존재 여부 확인. 없으면 스크립트가 에러로 종료.
- **`-VerifyContainer`** (Docker 사용 시):  
  `pws.ps1 -Docker -VerifyContainer` 로 빌드·기동 후, 일회성 컨테이너에서 다음 확인:
  - `/var/www/html/pathfinder/public/js/standalone-hook.js` 존재 및 첫 줄
  - `index.html` 안에 `standalone-hook` 문자열
  - `app/routes.ini` 안에 `Standalone` 라우트

### 5.3 수동으로 컨테이너 확인

```powershell
# 이미지 빌드 후 (예: pathfinder:local)
docker run --rm --entrypoint "" pathfinder:local /bin/sh -c "head -n 1 /var/www/html/pathfinder/public/js/standalone-hook.js; grep -o standalone-hook /var/www/html/pathfinder/public/templates/view/index.html; grep Standalone /var/www/html/pathfinder/app/routes.ini"
```

- `standalone-hook.js` 첫 줄이 `/* PF_STANDALONE_HOOK` 로 시작하고, `index.html`에서 `standalone-hook`, `routes.ini`에서 `Standalone` 이 보이면 반영된 것.

### 5.4 버전 불일치 시

- gulp 출력 디렉터리 이름은 `pathfinder/app/pathfinder.ini` 의 `PATHFINDER.VERSION` (예: 2.2.4) → `public/js/v2.2.4`.
- **루트 `Dockerfile`은 `v2.2.4` 를 하드코딩**해서 COPY함.  
  버전을 바꾼 경우 `Dockerfile`의 `COPY ./pathfinder/public/js/v2.2.4` 등도 같은 버전으로 맞출 것.
