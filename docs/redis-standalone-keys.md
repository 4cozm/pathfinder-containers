# Redis에서 스탠드얼론(다클라 헬퍼) 저장 데이터 확인

Docker 서버의 Redis에 스탠드얼론 프로그램이 DPoP 발급 후 채팅 로그에서 읽은 UID 정보가 잘 저장돼 있는지 확인하는 방법입니다.

## 1. Redis 접속 (Docker)

같은 호스트에서:

```bash
docker exec -it redis redis-cli
```

또는 PowerShell:

```powershell
docker exec -it redis redis-cli
```

## 2. 스탠드얼론 관련 키

| 키 패턴 | 타입 | 설명 |
|---------|------|------|
| **standalone:uids:{cid}** | Set | 다클라 헬퍼가 **standalone.bind** 시 보낸 **EVE 창 UID 목록**. 채팅 로그 스캔으로 얻은 UID들이 서버로 전달되면 여기에 SADD로 저장됨. `{cid}` = verify에서 나온 캐릭터 ID. |

저장 로직: `websocket/app/Component/MapUpdate.php`  
- `standalone.bind` 수신 시 `load.uids`가 있으면 `standaloneUidsPersist($cid, $uids)` 호출  
- Redis 키: `standalone:uids:{cid}`  
- `REDIS_DSN` 환경변수가 있으면 Predis로 SADD 수행, 없으면 스킵

## 3. 확인할 redis-cli 명령

```bash
# standalone 관련 키만 나열
KEYS standalone:*

# 특정 cid(예: 2122760050)의 UID Set 조회
SMEMBERS standalone:uids:2122760050

# Set 멤버 개수
SCARD standalone:uids:2122760050
```

예: 다클라 헬퍼로 verify 성공한 캐릭터 ID가 `2122760050`이면,  
`SMEMBERS standalone:uids:2122760050` 결과에 EVE 클라이언트 창 UID들이 있으면 **채팅 로그 → 서버 전달 → Redis 저장**이 정상 동작한 것입니다.

## 4. 저장이 안 보일 때 점검

1. **verify 성공 후 WS 연결·bind까지 진행했는지**  
   - dmc_helper 로그에 `[WS] 연결됨`, `standalone.bound` 수신 여부 확인.
2. **bind 시 uids를 보냈는지**  
   - dmc_helper는 EVE 창 스캔 결과(UIDS)를 `standalone.bind`의 `load.uids`에 담아 전송. uids가 비어 있으면 Redis에 SADD할 멤버가 없어서 키가 생기지 않을 수 있음.
3. **웹소켓 서버에 REDIS_DSN 설정 여부**  
   - `pf-socket`(websocket) 컨테이너의 `.env`에 `REDIS_DSN=tcp://redis:6379` 등이 있어야 Redis에 기록함.

## 5. `standalone:*` 키가 없을 때

- **KEYS standalone:*** 결과가 비어 있으면**: 아직 한 번도 `standalone.bind`가 **uids를 포함한 상태로** 성공하지 않았거나, 웹소켓 서버에 `REDIS_DSN`이 없어 저장을 스킵한 경우입니다.
- verify가 401로 실패하면 ticket이 없어 WS bind 자체가 진행되지 않으므로, 먼저 verify 성공 → WS 연결 → bind(uids 포함)까지 되었는지 확인하세요.

## 6. 요약

- **Redis 접속**: `docker exec -it redis redis-cli`
- **저장 확인**: `KEYS standalone:*` → `SMEMBERS standalone:uids:{cid}`  
- **의미**: `standalone:uids:{cid}` Set에 값이 있으면, 스탠드얼론 프로그램이 DPoP 발급 후 채팅 로그에서 읽은 UID를 서버로 전달했고, 서버가 Redis에 잘 저장한 상태입니다.

- **현재 이 Redis에서**: `KEYS standalone:*` 실행 시 키가 없으면, 위 조건(bind + uids + REDIS_DSN)이 한 번도 충족되지 않은 상태입니다.
