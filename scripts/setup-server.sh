#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# setup-server.sh — Configuracion inicial del servidor Hetzner (Ubuntu 24.04 LTS)
# Ejecutar como root: curl -sSL <url> | bash
# =============================================================================

DEPLOY_USER="deploy"
APP_DIR="/opt/sebasing"
REPO_URL="https://github.com/sebastianortiz/sebasing-infra.git"

echo "============================================="
echo "  Configuracion inicial — sebasing.dev"
echo "============================================="

# --- 1. Actualizar sistema ---
echo "[1/7] Actualizando sistema..."
apt-get update && apt-get upgrade -y

# --- 2. Instalar Docker ---
echo "[2/7] Instalando Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm /tmp/get-docker.sh
else
    echo "Docker ya esta instalado."
fi

# Instalar Docker Compose plugin
apt-get install -y docker-compose-plugin

# --- 3. Crear usuario deploy ---
echo "[3/7] Creando usuario deploy..."
if ! id "$DEPLOY_USER" &> /dev/null; then
    useradd -m -s /bin/bash "$DEPLOY_USER"
    usermod -aG docker "$DEPLOY_USER"
    mkdir -p /home/$DEPLOY_USER/.ssh
    cp /root/.ssh/authorized_keys /home/$DEPLOY_USER/.ssh/authorized_keys 2>/dev/null || true
    chown -R $DEPLOY_USER:$DEPLOY_USER /home/$DEPLOY_USER/.ssh
    chmod 700 /home/$DEPLOY_USER/.ssh
    chmod 600 /home/$DEPLOY_USER/.ssh/authorized_keys 2>/dev/null || true
    echo "$DEPLOY_USER ALL=(ALL) NOPASSWD: /usr/bin/docker, /usr/bin/docker-compose" >> /etc/sudoers.d/$DEPLOY_USER
    echo "Usuario '$DEPLOY_USER' creado y agregado al grupo docker."
else
    echo "Usuario '$DEPLOY_USER' ya existe."
fi

# --- 4. Configurar firewall ---
echo "[4/7] Configurando firewall (ufw)..."
apt-get install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp   # SSH
ufw allow 80/tcp   # HTTP
ufw allow 443/tcp  # HTTPS
ufw --force enable
echo "Firewall configurado: SSH (22), HTTP (80), HTTPS (443)."

# --- 5. Crear directorios ---
echo "[5/7] Creando directorios..."
mkdir -p "$APP_DIR"
mkdir -p "$APP_DIR/backups"
mkdir -p "$APP_DIR/ssl/certbot/conf"
mkdir -p "$APP_DIR/ssl/certbot/www"
chown -R $DEPLOY_USER:$DEPLOY_USER "$APP_DIR"

# --- 6. Clonar repositorio ---
echo "[6/7] Clonando repositorio de infraestructura..."
if [ ! -d "$APP_DIR/.git" ]; then
    su - $DEPLOY_USER -c "git clone $REPO_URL $APP_DIR"
else
    echo "Repositorio ya clonado."
fi

# --- 7. Preparar .env ---
echo "[7/7] Preparando archivo de entorno..."
if [ ! -f "$APP_DIR/.env" ]; then
    cp "$APP_DIR/.env.example" "$APP_DIR/.env"
    chown $DEPLOY_USER:$DEPLOY_USER "$APP_DIR/.env"
    chmod 600 "$APP_DIR/.env"
    echo "Archivo .env creado desde .env.example"
else
    echo "Archivo .env ya existe."
fi

echo ""
echo "============================================="
echo "  Configuracion completada"
echo "============================================="
echo ""
echo "Siguientes pasos:"
echo ""
echo "  1. Editar variables de produccion:"
echo "     nano $APP_DIR/.env"
echo ""
echo "  2. Generar certificados SSL:"
echo "     certbot certonly --standalone \\"
echo "       -d sebasing.dev \\"
echo "       -d www.sebasing.dev \\"
echo "       -d nexus-crm-api.sebasing.dev \\"
echo "       -d nexus-crm-dashboard.sebasing.dev \\"
echo "       -d nexus-crm-events-api.sebasing.dev \\"
echo "       -d nexus-crm-semantic-search-api.sebasing.dev"
echo ""
echo "  3. Copiar certificados:"
echo "     cp -rL /etc/letsencrypt/live $APP_DIR/ssl/certbot/conf/"
echo "     cp -rL /etc/letsencrypt/archive $APP_DIR/ssl/certbot/conf/"
echo ""
echo "  4. Desplegar:"
echo "     cd $APP_DIR && ./scripts/deploy.sh"
echo ""
