# Pathfinder build script (Node 12 + npm install + gulp)
# Usage: .\pws.ps1 [-SkipDocker] [-SkipNodeCheck] [-VerifyContainer] [-NoCache]
#   기본: gulp 후 docker-compose down → up --build -d (컨테이너 내렸다 올리기)
#   -SkipDocker     Docker 기동 생략 (gulp까지만 실행, Run Code 등에서 컨테이너 불필요할 때)
#   -SkipNodeCheck  Skip Node 12 version check (use current Node)
#   -VerifyContainer  Docker 후 컨테이너 내 산출물 반영 여부 확인
#   -NoCache        빌드 시 캐시 미사용 (parent snapshot 오류 시 사용)

param(
    [switch]$SkipDocker,
    [switch]$SkipNodeCheck,
    [switch]$VerifyContainer,
    [switch]$NoCache
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$PathfinderDir = Join-Path $ProjectRoot "pathfinder"

# Dockerfile이 복사하는 경로와 동일하게 검사 (상대 pathfinder/)
$RequiredBuildArtifacts = @(
    "pathfinder\public\js\standalone-hook.js"
    "pathfinder\public\js\v2.2.4"
    "pathfinder\public\css\v2.2.4"
    "pathfinder\public\templates\view\index.html"
    "pathfinder\app\routes.ini"
)

function Write-Step { param($Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Ok    { param($Message) Write-Host "OK: $Message" -ForegroundColor Green }
function Write-Warn  { param($Message) Write-Host "WARN: $Message" -ForegroundColor Yellow }
function Write-Err   { param($Message) Write-Host "ERROR: $Message" -ForegroundColor Red }

# SnoreToast (Windows 토스트) — 설치되어 있으면 성공/실패 시에만 표시 (어떤 스크립트에서든 사용 가능)
function Show-SnoreToast {
    param([string]$Title, [string]$Message)
    if (-not (Get-Command SnoreToast -ErrorAction SilentlyContinue)) { return }
    & SnoreToast -t $Title -m $Message 2>$null
}

function Exit-WithError {
    param([string]$Message)
    Write-Err $Message
    Show-SnoreToast -Title "pws.ps1 실패" -Message $Message
    exit 1
}

function Test-BuildArtifacts {
    $missing = @()
    foreach ($rel in $RequiredBuildArtifacts) {
        $full = Join-Path $ProjectRoot $rel
        if (-not (Test-Path $full)) {
            $missing += $rel
        }
    }
    return $missing
}

# --- 1. Node 12 사용 (nvm 등 있으면 전환) ---
if (-not $SkipNodeCheck) {
    Write-Step "Checking Node version (Pathfinder requires Node 12.x)..."

    $nvmPath = $env:NVM_HOME
    if (-not $nvmPath -and (Get-Command nvm -ErrorAction SilentlyContinue)) {
        $nvmPath = (Get-Command nvm).Source -replace "\\nvm\.cmd$", ""
    }
    if ($nvmPath) {
        Write-Host "Using nvm: $nvmPath"
        & "$nvmPath\nvm.exe" use 12 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "nvm use 12 failed or Node 12 not installed. Try: nvm install 12 && nvm use 12"
        }
        else { Write-Ok "Switched to Node 12" }
    }

    $nodeVersion = (node -v 2>$null) -replace "v", ""
    $major = [int]($nodeVersion -split "\.")[0]
    if ($major -ne 12) {
        Write-Warn "Current Node is $nodeVersion. Pathfinder expects Node 12.x. Use nvm use 12 or -SkipNodeCheck to continue anyway."
        $confirm = Read-Host "Continue with current Node? (y/N)"
        if ($confirm -ne "y" -and $confirm -ne "Y") { Exit-WithError "Aborted (Node version)" }
    }
    else { Write-Ok "Node $nodeVersion" }
}

# --- 2. pathfinder 디렉터리로 이동 ---
if (-not (Test-Path $PathfinderDir)) {
    Exit-WithError "pathfinder folder not found: $PathfinderDir"
}
Push-Location $PathfinderDir
try {

    # --- 3. npm install (필요 시) ---
    if (-not (Test-Path "node_modules")) {
        Write-Step "Running npm install in pathfinder..."
        npm install
        if ($LASTEXITCODE -ne 0) { Exit-WithError "npm install failed" }
        Write-Ok "npm install done"
    }

    # --- 4. npx gulp (Dart Sass 사용 — node-sass/Visual Studio 불필요) ---
    Write-Step "Running npx gulp production-noimg..."
    npx gulp production-noimg
    if ($LASTEXITCODE -ne 0) {
        Exit-WithError "npx gulp failed"
    }
    Write-Ok "npx gulp done (public/js/v2.2.4, public/css/v2.2.4)"

    # --- 4.1 빌드 산출물 검증 (Dockerfile COPY 대상이 반드시 존재해야 함) ---
    Pop-Location
    Set-Location $ProjectRoot
    $missing = Test-BuildArtifacts
    if ($missing.Count -gt 0) {
        Write-Err "Build artifacts missing (Docker COPY will fail):"
        foreach ($m in $missing) { Write-Host "  - $m" }
        Write-Host "  (standalone-hook.js는 저장소 파일, v2.2.4는 gulp로 생성. gulp가 완료됐는지 확인)" -ForegroundColor Yellow
        Exit-WithError "Build artifacts missing"
    }
    Write-Ok "Required artifacts present: standalone-hook.js, v2.2.4, templates, app/routes.ini"

    # --- 5. Docker: down 후 up (기본 동작, -SkipDocker 시 생략) ---
    if (-not $SkipDocker) {
        Set-Location $ProjectRoot
        Write-Step "Restarting stack (down then up)..."
        docker network inspect web 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { docker network create web 2>&1 | Out-Null }
        docker-compose down

        if ($NoCache) {
            Write-Step "Building with --no-cache (cache bypass)..."
            docker-compose build --no-cache
            if ($LASTEXITCODE -ne 0) { Exit-WithError "docker-compose build --no-cache failed" }
            docker-compose up -d
        }
        else {
            docker-compose up --build -d
        }

        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Build failed (e.g. parent snapshot not found). Retrying with --no-cache..."
            docker-compose build --no-cache
            if ($LASTEXITCODE -ne 0) { Exit-WithError "docker-compose build failed. Try: docker builder prune -f then .\pws.ps1 -NoCache" }
            docker-compose up -d
        }
        if ($LASTEXITCODE -ne 0) {
            Exit-WithError "docker-compose up failed"
        }
        Write-Ok "Containers restarted"
        Show-SnoreToast -Title "pws.ps1" -Message "Build & containers OK"

        if ($VerifyContainer) {
            Write-Step "Verify: 컨테이너 내 산출물 반영 여부 확인 (pathfinder:local)..."
            $check = "echo '--- standalone-hook.js ---'; test -f /var/www/html/pathfinder/public/js/standalone-hook.js && head -n 1 /var/www/html/pathfinder/public/js/standalone-hook.js || echo 'MISSING'; echo '--- index.html standalone-hook ---'; grep -o 'standalone-hook' /var/www/html/pathfinder/public/templates/view/index.html 2>/dev/null || echo 'NOT FOUND'; echo '--- routes.ini Standalone ---'; grep Standalone /var/www/html/pathfinder/app/routes.ini 2>/dev/null || echo 'NOT FOUND'"
            docker run --rm --entrypoint "" pathfinder:local /bin/sh -c $check
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "Verify run had non-zero exit (container may use different entrypoint)"
            }
            else {
                Write-Ok "Verify done. 위 출력에 standalone-hook 및 Standalone 라우트가 보이면 반영된 것."
            }
        }
        return
    }

}
finally {
    if ((Get-Location).Path -eq $PathfinderDir) { Pop-Location }
}

Write-Host ""
Write-Ok "Build finished (Docker skipped). Run without -SkipDocker to restart containers: .\pws.ps1"
Show-SnoreToast -Title "pws.ps1" -Message "Build OK (Docker skipped)"
