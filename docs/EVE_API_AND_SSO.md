# EVE ESI / SSO 사용 현황 (pathfinder-containers)

Pathfinder 앱은 [goryn-clade/pathfinder](https://github.com/goryn-clade/pathfinder) 서브모듈을 통해 EVE **ESI**(`https://esi.evetech.net`)와 **SSO**(`https://login.eveonline.com`)를 사용합니다.  
실제 HTTP 클라이언트는 Composer 의존성 **`goryn-clade/pathfinder_esi` 2.1.4** ([GitHub 릴리스 v2.1.4](https://github.com/goryn-clade/pathfinder_esi/releases/tag/v2.1.4), **게시일 2024-03-16**)입니다.

엔드포인트 경로는 **런타임에 swagger를 받아 오는 방식이 아니라**, 라이브러리 소스의 **정적 배열**(`Exodus4D\ESI\Config\Ccp\Esi\Config::$spec`)에 하드코딩되어 있습니다. CCP가 OpenAPI 3.x로 전환·구 `swagger.json`·`/status.json` 등을 폐기한 뒤에는 **이 맵을 최신 스펙에 맞게 갱신**(업스트림 릴리스, Fork, 또는 `vendor` 패치)해야 합니다.

---

## 1. 설정 키 (환경·ini)

| 용도 | 키 | 기본 예 |
|------|-----|---------|
| ESI 베이스 | `CCP_ESI_URL` | `https://esi.evetech.net` |
| 데이터소스 | `CCP_ESI_DATASOURCE` | `tranquility` |
| SSO 베이스 | `CCP_SSO_URL` | `https://login.eveonline.com` |
| JWT iss 검사 | `CCP_SSO_JWK_CLAIM` | `login.eveonline.com` |
| 이미지 (ESI 아님) | `CCP_IMAGE_SERVER` | `https://images.evetech.net` |

---

## 2. ESI 호출 요약

### 2.1 프론트엔드에서 직접 지정한 URL

- [pathfinder/js/app/ui/module/system_killboard.js](../pathfinder/js/app/ui/module/system_killboard.js):  
  `GET https://esi.evetech.net/latest/killmails/{killmail_id}/{killmail_hash}/`

### 2.2 PHP — `ccpClient()->send('핸들러')`

핸들러 이름은 Pathfinder 앱 전역에서 `grep "ccpClient()->send"`로 재확인할 수 있습니다.  
`pathfinder_esi`의 **정적 `$spec`**과 대응하는 대표 예는 다음과 같습니다.

- **메타·헬스** (`getStatus`): `meta` → `status` → **`GET` `/status.json`** (v2.1.4 소스 기준). CCP는 **구형 `/status.json` 폐기 및 `/meta/status` 계열로 대체**를 공지했으므로, **이 경로가 남아 있으면 ESI 메타 헬스 호출이 실패**할 수 있습니다. 최종 경로는 [ESI API Explorer](https://esi.evetech.net) 및 CCP 공지·OpenAPI 스펙으로 확인하세요.
- **Tranquility 서버 상태** (`getServerStatus`): **`GET` `/v1/status/`** (별도 리소스; `meta.status`와 혼동하지 말 것).

**캐릭터:** `getCharacter`, `getCharacterAffiliation`, `getCharacterRoles`, `getCharacterClones`, `getCharacterOnline`, `getCharacterLocation`, `getCharacterShip`

**코퍼 / 얼라 / NPC:** `getCorporation`, `getCorporationRoles`, `getNpcCorporations`, `getAlliance`

**유니버스 / 도그마:** `getUniverseSystems`, `getUniverseSystem`, `getUniverseRegion(s)`, `getUniverseConstellation(s)`, `getUniverseStar`, `getUniversePlanet`, `getUniverseStargate`, `getUniverseStation`, `getUniverseStructure`, `getUniverseType`, `getUniverseNames`, `search`, `getUniverseCategory(ies)`, `getUniverseGroup(s)`, `getUniverseFaction`, `getUniverseRace`, `getDogmaAttribute`, `getUniverseJumps`, `getUniverseKills`

**FW / 소버린티 / 라우트 / UI:** `getFactionWarSystems`, `getSovereigntyMap`, `getRoute`, `setWaypoint`, `openWindow`

**ESI 아님:** `eveScoutClient()->send('getTheraConnections')` — Eve Scout API.

### 2.3 이미지

- 예: `https://images.evetech.net/characters/{id}/portrait?size=64` ([pathfinder/app/Controller/Admin.php](../pathfinder/app/Controller/Admin.php) 등)

---

## 3. SSO / JWT

### 3.1 Pathfinder 앱이 실제로 호출하는 SSO

| 용도 | 코드 | pathfinder_esi 상대 경로 (v2.1.4) |
|------|------|-----------------------------------|
| 토큰 발급·갱신 | `ssoClient()->send('getAccess', ...)` | `POST /v2/oauth/token` |
| JWKS | `ssoClient()->send('getJWKS')` | `GET /oauth/jwks` |

JWT 검증은 **원격 `oauth/verify`가 아니라** `firebase/php-jwt`로 **JWKS로 서명 검증 후 로컬 디코드** ([pathfinder/app/Controller/Ccp/Sso.php](../pathfinder/app/Controller/Ccp/Sso.php) `verifyJwtAccessToken`).

### 3.2 `https://login.eveonline.com/v2/oauth/verify`

이 저장소 **애플리케이션 코드에는 `v2/oauth/verify` 호출이 없습니다** (`ssoClient()->send`는 `getAccess`·`getJWKS`만 사용).

### 3.3 라이브러리 내 레거시 `GET /oauth/verify`

`pathfinder_esi` **v2.1.4**의 `Sso.php`에는 `getVerifyUserEndpointURI()` → **`/oauth/verify`** 가 정의되어 있습니다. Pathfinder는 **호출하지 않지만**, 라이브러리 소비자가 `getVerify` 계열을 쓰면 CCP 정책(리다이렉트·삭제 예정 등)에 따라 깨질 수 있음.  
공식 대안으로 **`/v2/oauth/verify`** 등으로 맞추는 것은 **pathfinder_esi 업스트림 또는 Fork**에서 처리하는 것이 적절합니다.

### 3.4 혼동 주의

`Controller::getEveServerStatus`의 `getVerify()`는 **Guzzle TLS 인증서 검증 옵션**이며 OAuth 엔드포인트와 무관합니다.

---

## 4. 스펙·마이그레이션 메모

- 구형 **`swagger.json` 전용 URL**(예: `/dev/swagger.json`, 동결된 `/latest/swagger.json` 등)은 **단일 기준으로 쓰기 어려울 수 있음**. CCP가 **OpenAPI 3.0/3.1** 기준으로 안내하는 **현행 스펙 URL**은 [ESI 탐색기](https://esi.evetech.net) 및 개발자 블로그를 따릅니다.
- `pathfinder_esi`는 **빌드 타임에 생성된 정적 맵** 형태이므로, 스펙 변경 시 **라이브러리 릴리스 또는 Fork·패치**가 필요합니다.

---

## 5. 선택: `vendor` 패치 (프로덕션에서 `composer install` 후)

`pathfinder/patches/`에 **pathfinder_esi v2.1.4** 기준 예시 패치를 두었습니다.  
배포 서버에서 의존성을 설치한 뒤, 필요 시 `patch` 또는 `composer-patches` 등으로 적용할 수 있습니다.

- `pathfinder_esi-v2.1.4-ccp-endpoints.patch` — `meta.status`의 `/status.json` → `/meta/status/`(CCP 최종 경로는 스펙 확인 후 조정), `getVerifyUserEndpointURI` → `/v2/oauth/verify`

**주의:** 경로 문자열은 CCP 최신 OpenAPI 스펙과 일치하는지 반드시 검증하세요.
