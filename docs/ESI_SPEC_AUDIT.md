# ESI 최신 스펙 대조 감사 (2026-07-17)

EVE Online ESI가 2025년부터 **compatibility date 체계**(`X-Compatibility-Date` 헤더)로 전환되면서
(`/vN/` 버전 경로와 `/latest/swagger.json`은 동결·단계적 제거 중) 이 프로젝트가 손해 보던 지점을
전수 대조한 결과. 라이브 프로브(실제 ESI 호출)로 검증했다.

- ESI 클라이언트: `goryn-clade/pathfinder_esi` **v2.1.4** (composer, vendor는 이미지 빌드 시 설치)
- 앱 측 우회 레이어: `app/Lib/Api/EsiRouteStatusAdapter.php` (route/status 2개만 직접 호출)
- 유효 compat date 목록: `GET https://esi.evetech.net/meta/compatibility-dates`

---

## ✅ 수정 완료 (2026-07-17, EsiRouteStatusAdapter 재작성)

### P0-1. 맵 루트 검색 — 400으로 전면 고장이었음
- 원인: compat date `2018-04-03` 전송 → ESI가 400 거부 (최소 지원일 2020-01-01).
  스키마도 구식: `flag` → 신규는 `preference`(`Shorter|Safer|LessSecure`, 대소문자 엄격 — `"shorter"`는 422),
  `connections`가 `[[from,to],...]` → `[{"from":id,"to":id},...]` 객체 배열.
- 수정: compat date `2026-06-09` 핀(클래스 상수) + 무버전 `POST /route/{o}/{d}` + 스키마 변환.
  **주의**: 신규 응답이 이미 `{"route":[...]}` 형태라 재래핑하면 안 됨.
- 검증: Jita→Amarr 커스텀 커넥션 직결(2시스템) / shortest(12시스템) / 도달불가 에러 표면화 — E2E 통과.
- 참고: 구 `GET /v1/route/`는 아직 200이지만 CCP가 제거 예고
  ([Route to the future](https://developers.eveonline.com/blog/route-to-the-future-upgrading-the-route-route)).

### P0-2. ESI 상태 다이얼로그 — 404로 고장이었음
- 원인: `GET /meta/status`를 compat date 헤더 없이 호출 → 404. 구 `/status.json`은 2026-03-24 제거됨
  ([Spring Cleaning](https://developers.eveonline.com/blog/spring-cleaning-legacy-routes-removed-24-march-2026)).
  상태값도 `green/yellow/red` → `OK/Degraded/Down/Recovering`으로 변경됨.
- 수정: 헤더 추가 + 신 상태값→구 색상 번역을 **어댑터 경계에서** 처리
  (`Controller.php` 판정 로직·프론트 템플릿 `api_status.html` 무수정).

---

## ⚠️ 미수정 — vendor 포크(goryn-clade/pathfinder_esi) 필요

우선순위순. 고치려면 pathfinder_esi를 4cozm으로 포크해 composer.json 교체가 선행돼야 한다.

| 우선순위 | 이슈 | 상세 |
|---|---|---|
| P1 | **Sovereignty 구 엔드포인트** | `app/Cron/Universe.php`가 `/v1/sovereignty/map/`(최신 스펙 뷰에서 제거됨) 사용. 대체 `GET /sovereignty/systems`는 캐시 300s ← 기존 3600s → 현재 주권 데이터가 최대 12배 낡음. 크론(`cron.ini` `@halfPastHour`)도 5분 주기로 당길 수 있음 |
| P1 | **X-Compatibility-Date 전역 미지원** | 클라이언트 전체가 `/vN/` 고정 경로. CCP 마이그레이션 창(2025-07부터 약 1년)이 만료 시점 — 다음 배치 제거 대상. 현재 사용 27개 라우트는 아직 전부 유효(전수 확인) |
| P2 | **429 Retry-After 미준수** | 2025-10 도입된 토큰버킷 rate limit(routes/sovereignty/location·online·ship 그룹 — 전부 Pathfinder 핵심 호출). `GuzzleRetryMiddleware`가 429를 고정 백오프로 재시도해 4XX 토큰(5개)만 추가 소모. `X-Ratelimit-*` 헤더 감시도 없음 ([Hold your horses](https://developers.eveonline.com/blog/hold-your-horses-introducing-rate-limiting-to-esi)) |
| P2 | **/universe/groups 페이지네이션 누락** | `X-Pages: 2`인데 1페이지만 수집 → **그룹 ~500개 유실 중** (universe 초기 셋업 크론) |
| P3 | 클라이언트 `meta./status.json` 정의 잔존 | 죽은 경로(404) — 앱은 어댑터로 우회하므로 실해 없음 |

## ✅ 문제 없던 것 (참고)

- 캐시 TTL: location 5s, online(Guzzle 캐시가 Expires 흡수), jumps/kills 1시간 크론 등 스펙과 일치
- HTTP 위생: Expires/max-age 자동 준수, ETag→If-None-Match(304), `x-esi-error-limit-remain` 감시
  (잔여 10 미만 시 차단), 식별 가능한 User-Agent — 전부 클라이언트가 이미 처리
- 2025-03-25 1차 제거 라우트들(stations v1 등)은 이미 상위 버전 사용 중이라 무피해

## 유지보수 메모

- compat date를 올릴 때: `meta/compatibility-dates`에서 유효 날짜 확인 → route/status 응답
  스키마 변화 검토 → `EsiRouteStatusAdapter::COMPATIBILITY_DATE` 갱신 → E2E 재검증.
- 어댑터 호출은 `pf_esi_request_duration_seconds{endpoint="adapterGetRoute|adapterGetStatus"}`로
  관측되고, 실패 시 `[ESI_ADAPTER_FAIL]` 로그가 docker logs(→ Loki)에 남는다.
