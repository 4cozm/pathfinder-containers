#!/bin/bash
# Pathfinder build script for Ubuntu (Node 12 + npm install + gulp)
# Usage: ./pws.sh [--skip-docker] [--skip-node-check] [--verify-container] [--no-cache]

set -e # 명령어 실패 시 즉시 중단

PROJECT_ROOT=$(pwd)
PATHFINDER_DIR="$PROJECT_ROOT/pathfinder"

# Dockerfile이 복사하는 경로와 동일하게 검사
REQUIRED_BUILD_ARTIFACTS=(
    "pathfinder/public/js/standalone-hook.js"
    "pathfinder/public/js/v2.2.4"
    "pathfinder/public/css/v2.2.4"
    "pathfinder/public/templates/view/index.html"
    "pathfinder/app/routes.ini"
)

# 색상 함수
write_step() { echo -e "\n\e[36m==> $1\e[0m"; }
write_ok()   { echo -e "\e[32mOK: $1\e[0m"; }
write_warn() { echo -e "\e[33mWARN: $1\e[0m"; }
write_err()  { echo -e "\e[31mERROR: $1\e[0m"; }

exit_with_error() {
    write_err "$1"
    exit 1
}

test_build_artifacts() {
    local missing=()
    for rel in "${REQUIRED_BUILD_ARTIFACTS[@]}"; do
        if [ ! -e "$PROJECT_ROOT/$rel" ]; then
            missing+=("$rel")
        fi
    done
    echo "${missing[@]}"
}

# 인자 처리
SKIP_DOCKER=false
SKIP_NODE_CHECK=false
VERIFY_CONTAINER=false
NO_CACHE=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --skip-docker) SKIP_DOCKER=true ;;
        --skip-node-check) SKIP_NODE_CHECK=true ;;
        --verify-container) VERIFY_CONTAINER=true ;;
        --no-cache) NO_CACHE=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# --- 1. Node 12 사용 (nvm 인식) ---
if [ "$SKIP_NODE_CHECK" = false ]; then
    write_step "Checking Node version (Pathfinder requires Node 12.x)..."
    
    # nvm 로딩 시도
    if [ -f "$HOME/.nvm/nvm.sh" ]; then
        source "$HOME/.nvm/nvm.sh"
        nvm use 12 || write_warn "nvm use 12 failed. Trying to continue with current node."
    fi

    NODE_VERSION=$(node -v 2>/dev/null | sed 's/v//') || exit_with_error "Node is not installed."
    MAJOR_VERSION=$(echo $NODE_VERSION | cut -d. -f1)

    if [ "$MAJOR_VERSION" -ne 12 ]; then
        write_warn "Current Node is $NODE_VERSION. Pathfinder expects Node 12.x."
        read -p "Continue anyway? (y/N) " confirm
        if [[ $confirm != [yY] ]]; then exit_with_error "Aborted (Node version)"; fi
    else
        write_ok "Node $NODE_VERSION"
    fi
fi

# --- 2. pathfinder 디렉터리로 이동 ---
if [ ! -d "$PATHFINDER_DIR" ]; then
    exit_with_error "pathfinder folder not found: $PATHFINDER_DIR"
fi
cd "$PATHFINDER_DIR"

# --- 3. npm install ---
if [ ! -d "node_modules" ]; then
    write_step "Running npm install in pathfinder..."
    npm install
    write_ok "npm install done"
fi

# --- 4. npx gulp ---
write_step "Running npx gulp production-noimg..."
npx gulp production-noimg || exit_with_error "npx gulp failed"
write_ok "npx gulp done"

# --- 4.1 빌드 산출물 검증 ---
cd "$PROJECT_ROOT"
MISSING_FILES=$(test_build_artifacts)
if [ ! -z "$MISSING_FILES" ]; then
    write_err "Build artifacts missing (Docker COPY will fail):"
    for m in $MISSING_FILES; do echo "  - $m"; done
    exit_with_error "Build artifacts missing"
fi
write_ok "Required artifacts present."

# --- 5. Docker ---
if [ "$SKIP_DOCKER" = false ]; then
    write_step "Restarting stack..."
    
    # Network check
    docker network inspect web >/dev/null 2>&1 || docker network create web >/dev/null 2>&1
    
    docker-compose down
    
    if [ "$NO_CACHE" = true ]; then
        write_step "Building with --no-cache..."
        docker-compose build --no-cache
        docker-compose up -d
    else
        docker-compose up --build -d
    fi
    
    write_ok "Containers restarted"

    if [ "$VERIFY_CONTAINER" = true ]; then
        write_step "Verify: 컨테이너 내 산출물 반영 여부 확인..."
        CHECK_CMD="echo '--- standalone-hook.js ---'; test -f /var/www/html/pathfinder/public/js/standalone-hook.js && head -n 1 /var/www/html/pathfinder/public/js/standalone-hook.js || echo 'MISSING';"
        docker run --rm --entrypoint "" pathfinder:local /bin/sh -c "$CHECK_CMD"
        write_ok "Verify done."
    fi
else
    write_ok "Build finished (Docker skipped)."
fi
