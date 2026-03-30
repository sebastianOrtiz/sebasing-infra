#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# deploy-service.sh — Despliega un servicio individual
# Uso: ./deploy-service.sh <nombre-servicio>
# Ejemplo: ./deploy-service.sh nexus-crm-api
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"

VALID_SERVICES=(
    "portfolio-web"
    "nexus-crm-api"
    "nexus-crm-dashboard"
    "event-api"
    "event-workers"
    "search-api"
)

usage() {
    echo "Uso: $0 <nombre-servicio>"
    echo ""
    echo "Servicios disponibles:"
    for s in "${VALID_SERVICES[@]}"; do
        echo "  - $s"
    done
    exit 1
}

if [ $# -ne 1 ]; then
    usage
fi

SERVICE_NAME="$1"

# Validar nombre de servicio
VALID=false
for s in "${VALID_SERVICES[@]}"; do
    if [ "$s" = "$SERVICE_NAME" ]; then
        VALID=true
        break
    fi
done

if [ "$VALID" = false ]; then
    echo "ERROR: Servicio '$SERVICE_NAME' no es valido."
    echo ""
    usage
fi

cd "$PROJECT_DIR"

echo "============================================="
echo "  Desplegando servicio: $SERVICE_NAME"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================="

# --- 1. Pull de la imagen ---
echo ""
echo "[1/3] Descargando imagen de $SERVICE_NAME..."
docker compose -f "$COMPOSE_FILE" pull "$SERVICE_NAME"

# --- 2. Reiniciar servicio ---
echo ""
echo "[2/3] Reiniciando $SERVICE_NAME..."
docker compose -f "$COMPOSE_FILE" up -d --no-deps --force-recreate "$SERVICE_NAME"

# --- 3. Verificar ---
echo ""
echo "[3/3] Verificando estado..."
sleep 5

CONTAINER="$(docker compose -f "$COMPOSE_FILE" ps -q "$SERVICE_NAME" 2>/dev/null || true)"
if [ -n "$CONTAINER" ]; then
    STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo "unknown")
    echo "  $SERVICE_NAME: $STATUS"

    if [ "$STATUS" != "running" ]; then
        echo ""
        echo "ADVERTENCIA: El servicio no esta en estado 'running'."
        echo "Revisa los logs con: docker compose logs $SERVICE_NAME"
        exit 1
    fi
else
    echo "ERROR: No se encontro el contenedor de $SERVICE_NAME."
    exit 1
fi

echo ""
echo "Deploy de $SERVICE_NAME completado."
