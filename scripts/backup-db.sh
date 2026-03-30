#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# backup-db.sh — Backup de PostgreSQL con rotacion
# Crontab: 0 3 * * * /opt/sebasing/scripts/backup-db.sh >> /opt/sebasing/backups/backup.log 2>&1
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
BACKUP_DIR="$PROJECT_DIR/backups"
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/sebasing_${TIMESTAMP}.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "============================================="
echo "  Backup PostgreSQL"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================="

# Obtener el nombre del contenedor de postgres
CONTAINER="$(docker compose -f "$COMPOSE_FILE" ps -q postgres 2>/dev/null || true)"

if [ -z "$CONTAINER" ]; then
    echo "ERROR: Contenedor de PostgreSQL no encontrado."
    echo "Asegurate de que los servicios estan corriendo."
    exit 1
fi

# Leer credenciales desde .env
if [ -f "$PROJECT_DIR/.env" ]; then
    # shellcheck source=/dev/null
    source "$PROJECT_DIR/.env"
fi

PG_USER="${POSTGRES_USER:-postgres}"

# Realizar backup
echo "Realizando backup..."
docker exec "$CONTAINER" pg_dumpall -U "$PG_USER" | gzip > "$BACKUP_FILE"

# Verificar que el backup no este vacio
BACKUP_SIZE=$(stat -f%z "$BACKUP_FILE" 2>/dev/null || stat -c%s "$BACKUP_FILE" 2>/dev/null || echo "0")
if [ "$BACKUP_SIZE" -lt 100 ]; then
    echo "ADVERTENCIA: El backup parece estar vacio o corrupto (${BACKUP_SIZE} bytes)."
    exit 1
fi

echo "Backup guardado: $BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1))"

# Eliminar backups antiguos
echo "Eliminando backups de mas de $RETENTION_DAYS dias..."
DELETED=$(find "$BACKUP_DIR" -name "sebasing_*.sql.gz" -mtime +$RETENTION_DAYS -delete -print | wc -l)
echo "Backups eliminados: $DELETED"

echo ""
echo "Backup completado exitosamente."
