#!/usr/bin/env bash
# Pathfinder Containers - Ubuntu 24 한 방 설정 스크립트
# 사용법:
#   (저장소 클론 후 실행)
#   git clone --recurse-submodules https://github.com/goryn-clade/pathfinder-containers.git
#   cd pathfinder-containers && sudo ./scripts/setup-ubuntu24.sh
#
#   (설치 경로 지정하여 클론+설치 한 번에)
#   sudo ./scripts/setup-ubuntu24.sh /opt/pathfinder-containers
#
set -e

INSTALL_DIR="${1:-}"
REPO_URL="${PATHFINDER_REPO_URL:-https://github.com/goryn-clade/pathfinder-containers.git}"
WORK_DIR=

err() { echo "[ERR] $*" >&2; exit 1; }
log() { echo "[OK] $*"; }

# root 또는 sudo
if [[ $EUID -ne 0 ]]; then
  err "root 권한이 필요합니다. sudo ./scripts/setup-ubuntu24.sh 로 실행하세요."
fi

# Ubuntu 확인 (24/22 허용)
if command -v lsb_release &>/dev/null; then
  case "$(lsb_release -cs)" in
    noble|jammy) log "Ubuntu $(lsb_release -cs) 감지" ;;
    *) err "Ubuntu 22.04(jammy) 또는 24.04(noble)에서만 실행하세요." ;;
  esac
else
  log "lsb_release 없음, Docker 설치만 진행"
fi

# 1) 작업 디렉터리 결정: 이미 저장소 안이면 여기서 진행, 아니면 클론
if [[ -f docker-compose.yml && -f .env.example ]]; then
  WORK_DIR="$(pwd)"
  log "저장소 내부에서 실행됨: $WORK_DIR"
elif [[ -n "$INSTALL_DIR" ]]; then
  if [[ -d "$INSTALL_DIR" && -f "$INSTALL_DIR/docker-compose.yml" ]]; then
    WORK_DIR="$(cd "$INSTALL_DIR" && pwd)"
    log "기존 설치 경로 사용: $WORK_DIR"
  else
    apt-get update -qq && apt-get install -y -qq git
    git clone --recurse-submodules "$REPO_URL" "$INSTALL_DIR"
    WORK_DIR="$(cd "$INSTALL_DIR" && pwd)"
    log "클론 완료: $WORK_DIR"
  fi
else
  err "저장소 루트에서 실행하거나, 설치 경로를 인자로 주세요. 예: sudo $0 /opt/pathfinder-containers"
fi

cd "$WORK_DIR"

# 2) Docker 설치 (없을 때만)
if ! command -v docker &>/dev/null; then
  log "Docker 설치 중..."
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sh /tmp/get-docker.sh
  rm -f /tmp/get-docker.sh
  log "Docker 설치 완료. (비 root 사용 시: usermod -aG docker \$USER 후 재로그인)"
else
  log "Docker 이미 설치됨: $(docker --version)"
fi

# 3) .env 생성 (없을 때만)
if [[ ! -f .env ]]; then
  cp .env.example .env
  # PROJECT_ROOT를 절대경로로
  if grep -q '^PROJECT_ROOT=' .env; then
    sed -i "s|^PROJECT_ROOT=.*|PROJECT_ROOT=$WORK_DIR|" .env
  else
    echo "PROJECT_ROOT=$WORK_DIR" >> .env
  fi
  log ".env 생성됨 (PROJECT_ROOT=$WORK_DIR). DOMAIN, APP_PASSWORD, CCP_SSO_*, LE_EMAIL 등은 수정 필요."
else
  log ".env 이미 있음"
fi

# 4) Traefik용 외부 네트워크
if ! docker network inspect web &>/dev/null 2>&1; then
  docker network create web
  log "Docker 네트워크 'web' 생성"
else
  log "Docker 네트워크 'web' 이미 있음"
fi

# 5) 컨테이너 기동
log "docker compose up -d 실행..."
docker compose up -d

echo ""
echo "=============================================="
echo "  Pathfinder Containers 기동 완료"
echo "=============================================="
echo ""
echo "다음 단계:"
echo "  1. .env 수정: DOMAIN, APP_PASSWORD, CCP_SSO_CLIENT_ID, CCP_SSO_SECRET_KEY, LE_EMAIL"
echo "  2. config/pathfinder/pathfinder.ini 필요 시 수정 (NAME, LOGIN 등)"
echo "  3. 브라우저에서 https://<DOMAIN>/setup 접속"
echo "     - 로그인: 사용자 pf, 비밀번호는 .env의 APP_PASSWORD"
echo "     - DB 섹션에서 'create database' → 'setup tables' → 'fix columns/keys'"
echo "  4. Eve Universe 덤프 임포트:"
echo "     docker compose exec pfdb /bin/sh -c 'unzip -p /eve_universe.sql.zip | mysql -u root -p\$MYSQL_ROOT_PASSWORD eve_universe'"
echo "  5. 프로덕션용: docker-compose.yml의 traefik 서비스에서 Let's Encrypt staging 라인 제거 후, ./letsencrypt/acme.json 삭제"
echo ""
echo "작업 디렉터리: $WORK_DIR"
echo ""
