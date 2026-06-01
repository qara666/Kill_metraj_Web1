#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
# Kill Metraj — локальный автодеплой на выделенном хосте
# ───────────────────────────────────────────────────────────
# Запускается НА хосте (через Gitea Actions по SSH или вручную).
# Неинтерактивный. Поднимает prod-стек целиком.
#   bash scripts/autodeploy.sh
# ═══════════════════════════════════════════════════════════
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn()   { echo -e "${YELLOW}[!]${NC} $*"; }
error()  { echo -e "${RED}[✗]${NC} $*"; }
header() { echo -e "\n${CYAN}══ $* ══${NC}"; }

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# --env-file: compose читает backend/.env и для ${...}-подстановки, и для
# контейнера. НЕ используем `source` — значения с &,),^ ломали бы bash.
COMPOSE="docker compose --env-file backend/.env -f docker-compose.prod.yml"

# ─── Проверки ──────────────────────────────────────────
header "Pre-flight"
command -v docker >/dev/null || { error "Docker не установлен"; exit 1; }
docker compose version >/dev/null || { error "Docker Compose v2 не найден"; exit 1; }
info "docker $(docker --version | awk '{print $3}' | tr -d ,), compose $(docker compose version --short)"

if [ ! -f backend/.env ]; then
    error "backend/.env не найден. Создай его на хосте (он gitignored) перед деплоем."
    exit 1
fi
info "backend/.env найден"

# ─── Сборка и запуск ───────────────────────────────────
header "Build & up"
$COMPOSE up --build -d

# ─── Caddy: подхватить актуальный Caddyfile ─────────────
# Caddyfile примонтирован как ОДИН файл. git pull/sed заменяют его новым inode,
# а работающий контейнер держит старый inode и правок не видит (reload бесполезен).
# Поэтому принудительно пересоздаём caddy — он перемонтирует текущий файл.
header "Caddy (пересоздание для подхвата Caddyfile)"
$COMPOSE up -d --force-recreate caddy && info "Caddy пересоздан"

# ─── Готовность ────────────────────────────────────────
# backend наружу не публикуется; фронтовый nginx (127.0.0.1:8080)
# проксирует /health на backend.
header "Readiness"
READY=0
for i in $(seq 1 30); do
    if curl -sf http://127.0.0.1:8080/health/readiness >/dev/null 2>&1; then
        info "backend готов (через frontend:8080)"; READY=1; break
    fi
    sleep 2
done
[ "$READY" = 1 ] || warn "backend не ответил за 60с — проверь: $COMPOSE logs backend"

# ─── Разовый импорт дампа БД ───────────────────────────
# Импортируем backup/latest.dump один раз, затем переименовываем,
# чтобы повторные деплои НЕ затирали данные.
if [ -f backup/latest.dump ]; then
    header "DB import (одноразовый)"
    if $COMPOSE exec -T postgres sh -c \
        'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner --no-acl' \
        < backup/latest.dump; then
        TS="$(date +%Y%m%d-%H%M%S)"
        mv backup/latest.dump "backup/latest.dump.imported-$TS"
        info "Дамп импортирован и помечен как imported-$TS"
    else
        warn "Импорт завершился с ошибкой (для пустой БД это может быть нормой)"
    fi
fi

# ─── Финал ─────────────────────────────────────────────
header "Cleanup"
docker image prune -f >/dev/null && info "старые образы очищены"

header "Status"
$COMPOSE ps
