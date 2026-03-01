# DT_JSON 패치 맥락 (가설 검증)

## 전제
- **어제까지**: 여러 번의 패치에도 잘 동작함.
- **오늘**: 수동 업데이트에서도 안 됨 → 원인이 "오늘 작업"에 있다는 가설.

## 빌드 경로 정리

| 경로 | Dockerfile | vendor 출처 | DT_JSON 패치 |
|------|------------|-------------|--------------|
| **pws.ps1 / docker-compose `pf`** | 루트 `Dockerfile` | 베이스 이미지 제거 후 `composer install` (lock 기준) | ✅ 적용됨 |
| **수동 빌드** | `pathfinder.Dockerfile` | `COPY pathfinder` 후 `composer install` | ❌ **적용 안 됨** |

## 가설 검증

1. **“오늘 작업”이 원인인가?**
   - **맞음.** 루트 Dockerfile은 오늘 작업에서 `rm -rf vendor` + `composer install`을 넣으면서 **베이스 vendor를 쓰지 않고** lock 기준 새 설치를 하게 됨.  
   - 수동 빌드(pathfinder.Dockerfile)는 **원래부터** `composer install`만 하고 패치는 없음.  
   - 따라서 “어제까지 됐다” = 예전에는  
     - 루트로 빌드할 때는 **베이스 이미지 vendor**를 그대로 썼거나,  
     - 수동 빌드를 안 썼거나,  
     - pathfinder 쪽에 이미 DT_JSON이 있는 vendor/포크가 있었을 가능성.  
   - “오늘 수동 업데이트에서 안 된다” = **수동 빌드(pathfinder.Dockerfile)**로 이미지를 만들면 `composer install` 결과에는 DT_JSON이 없고, 여기엔 패치가 없음.

2. **코드 수정 방향(패치로 Schema에 DT_JSON 추가)이 맞는가?**
   - **맞음.** f3-schema-builder에는 DT_JSON이 없고, Pathfinder/Cortex는 `Schema::DT_JSON`을 사용하므로, **어느 경로로 빌드하든** composer install 직후 vendor에 DT_JSON을 넣어 주는 패치가 필요함.

3. **왜 “수동 업데이트”에서만 안 되는가?**
   - 루트 Dockerfile로 빌드하면 패치 단계가 있어서 동작함.
   - **수동 빌드(pathfinder.Dockerfile)**는 패치 단계가 없어서, 같은 lock으로 설치해도 DT_JSON이 없는 상태로 이미지가 만들어짐.

## 결론
- 가설: **“오늘 작업(루트 Dockerfile의 vendor 재설치 + 패치)과 별개로, 수동 빌드 경로에는 패치가 없어서 수동 업데이트에서만 실패한다”** → **맞음.**
- 수정 방향: **Schema에 DT_JSON을 넣는 패치**는 올바름.  
- 추가 조치: **pathfinder.Dockerfile(수동 빌드)에도 동일 패치를 적용**해야, 수동 업데이트 후 빌드한 이미지에서도 DT_JSON 오류가 나지 않음.
