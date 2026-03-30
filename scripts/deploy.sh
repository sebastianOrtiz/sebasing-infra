#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# deploy.sh — Despliega todos los servicios de sebasing.dev
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"

echo "============================================="
echo "  Desplegando sebasing.dev"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================="

cd "$PROJECT_DIR"

# --- 1. Verificar .env ---
if [ ! -f .env ]; then
    echo "ERROR: Archivo .env no encontrado en $PROJECT_DIR"
    echo "Copia .env.example a .env y configura las variables."
    exit 1
fi

# --- 2. Pull de imagenes ---
echo ""
echo "[1/4] Descargando imagenes..."
docker compose -f "$COMPOSE_FILE" pull

# --- 3. Levantar servicios ---
echo ""
echo "[2/4] Levantando servicios..."
docker compose -f "$COMPOSE_FILE" up -d --remove-orphans

# --- 4. Esperar a que los servicios arranquen ---
echo ""
echo "[3/4] Esperando a que los servicios arranquen..."
sleep 15

# --- 5. Health checks ---
echo ""
echo "[4/4] Verificando salud de los servicios..."
echo ""

SERVICES=(
    "portfolio-web:3000:/"
    "nexus-crm-api:8000:/health"
    "nexus-crm-dashboard:80:/"
    "event-api:8081:/health"
    "search-api:8082:/health"
)

ALL_OK=true

for SERVICE_INFO in "${SERVICES[@]}"; do
    IFS=':' read -r NAME PORT PATH <<< "$SERVICE_INFO"
    CONTAINER="$(docker compose -f "$COMPOSE_FILE" ps -q "$NAME" 2>/dev/null || true)"

    if [ -z "$CONTAINER" ]; then
        printf "  %-25s %s\n" "$NAME" "NO ENCONTRADO"
        ALL_OK=false
        continue
    fi

    STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo "unknown")
    if [ "$STATUS" = "running" ]; then
        printf "  %-25s %s\n" "$NAME" "OK (running)"
    else
        printf "  %-25s %s\n" "$NAME" "FALLO ($STATUS)"
        ALL_OK=false
    fi
done

# Infraestructura
echo ""
echo "Infraestructura:"
for INFRA_SERVICE in postgres redis chromadb; do
    CONTAINER="$(docker compose -f "$COMPOSE_FILE" ps -q "$INFRA_SERVICE" 2>/dev/null || true)"
    if [ -z "$CONTAINER" ]; then
        printf "  %-25s %s\n" "$INFRA_SERVICE" "NO ENCONTRADO"
        ALL_OK=false
        continue
    fi
    STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo "unknown")
    HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo "n/a")
    printf "  %-25s %s (health: %s)\n" "$INFRA_SERVICE" "$STATUS" "$HEALTH"
done

echo ""
echo "============================================="
if [ "$ALL_OK" = true ]; then
    echo "  Deploy completado exitosamente"
else
    echo "  Deploy completado con advertencias"
    echo "  Revisa los servicios con: docker compose logs <servicio>"
fi
echo "============================================="

# Mostrar estado final
echo ""
docker compose -f "$COMPOSE_FILE" ps
