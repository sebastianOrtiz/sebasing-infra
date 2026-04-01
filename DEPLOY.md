# Guia de despliegue — sebasing.dev

Proceso completo para desplegar el ecosistema en un servidor Hetzner desde cero.

## 1. Crear el servidor

- **Proveedor**: Hetzner Cloud
- **Plan**: CPX32 (o similar con 4+ GB RAM para el modelo de embeddings)
- **OS**: Ubuntu 24.04 LTS
- **Ubicacion**: Helsinki (o la mas cercana)
- **IP actual**: 204.168.205.231

## 2. Configurar el servidor (como root)

```bash
# Actualizar sistema
apt update && apt upgrade -y

# Instalar Docker
curl -fsSL https://get.docker.com | sh

# Crear usuario deploy
adduser deploy
usermod -aG docker deploy

# Configurar SSH para el usuario deploy
mkdir -p /home/deploy/.ssh
cp ~/.ssh/authorized_keys /home/deploy/.ssh/
chown -R deploy:deploy /home/deploy/.ssh

# Firewall
ufw allow 22
ufw allow 80
ufw allow 443
ufw enable
```

## 3. Configurar DNS

En el panel del registrador de dominio, crear registros A apuntando al servidor:

| Registro | Tipo | Valor | TTL |
|---|---|---|---|
| `sebasing.dev` | A | 204.168.205.231 | 3600 |
| `www.sebasing.dev` | A | 204.168.205.231 | 3600 |
| `nexus-crm-api.sebasing.dev` | A | 204.168.205.231 | 3600 |
| `nexus-crm-dashboard.sebasing.dev` | A | 204.168.205.231 | 3600 |
| `nexus-crm-events-api.sebasing.dev` | A | 204.168.205.231 | 3600 |
| `nexus-crm-semantic-search-api.sebasing.dev` | A | 204.168.205.231 | 3600 |

## 4. Clonar repositorios (como usuario deploy)

```bash
ssh deploy@204.168.205.231

cd ~
git clone https://github.com/sebastianOrtiz/portfolio-web.git
git clone https://github.com/sebastianOrtiz/nexus-crm-api.git
git clone https://github.com/sebastianOrtiz/nexus-crm-dashboard.git
git clone https://github.com/sebastianOrtiz/event-driven-service.git
git clone https://github.com/sebastianOrtiz/semantic-search-api.git
git clone https://github.com/sebastianOrtiz/sebasing-infra.git infra
```

## 5. Construir imagenes Docker

Cada imagen se construye localmente en el servidor:

```bash
cd ~/portfolio-web
docker build -t ghcr.io/sebastianortiz/portfolio-web:latest .

cd ~/nexus-crm-api
docker build -t ghcr.io/sebastianortiz/nexus-crm-api:latest .

cd ~/nexus-crm-dashboard
docker build -t ghcr.io/sebastianortiz/nexus-crm-dashboard:latest .

cd ~/event-driven-service
docker build -t ghcr.io/sebastianortiz/event-driven-service:latest .

cd ~/semantic-search-api
docker build -t ghcr.io/sebastianortiz/semantic-search-api:latest .
```

## 6. Configurar variables de entorno

```bash
cd ~/infra
cp .env.example .env
nano .env
```

Contenido del `.env` (generar valores nuevos para cada instalacion):

```env
POSTGRES_USER=sebasing
POSTGRES_PASSWORD=<generar: openssl rand -hex 16>
POSTGRES_DB=sebasing
DATABASE_URL=postgresql://sebasing:<password>@postgres:5432/sebasing

REDIS_PASSWORD=<generar: openssl rand -hex 16>
REDIS_URL=redis://:<password>@redis:6379/0

JWT_SECRET_KEY=<generar: openssl rand -hex 32>
EVENT_SERVICE_API_KEY=<generar: openssl rand -hex 32>

ALLOWED_ORIGINS=https://sebasing.dev,https://nexus-crm-dashboard.sebasing.dev,https://nexus-crm-api.sebasing.dev
```

> **Nota**: Los servicios Go (event-api, event-workers) usan `REDIS_URL: "redis:6379"` hardcodeado en docker-compose.yml y reciben `REDIS_PASSWORD` por separado, porque go-redis espera `host:port` y no formato URL.

## 7. Levantar todos los servicios

```bash
cd ~/infra
docker compose up -d
```

Verificar que todo esta sano:

```bash
docker compose ps -a
```

Todos los servicios deben estar `healthy` o `Up`.

## 8. Generar certificados SSL

```bash
cd ~/infra
docker compose run --rm --entrypoint "certbot" certbot certonly --webroot -w /var/www/certbot \
  -d sebasing.dev \
  -d www.sebasing.dev \
  -d nexus-crm-api.sebasing.dev \
  -d nexus-crm-dashboard.sebasing.dev \
  -d nexus-crm-events-api.sebasing.dev \
  -d nexus-crm-semantic-search-api.sebasing.dev \
  --email sebastianortiz989@gmail.com \
  --agree-tos \
  --no-eff-email
```

> **Importante**: Usar `--entrypoint "certbot"` porque el servicio certbot tiene un entrypoint custom (loop de renovacion) que ignora los argumentos.

Verificar que se generaron:

```bash
ls ssl/certbot/conf/live/sebasing.dev/
# Debe mostrar: fullchain.pem  privkey.pem  ...
```

Los configs de Nginx ya estan configurados para HTTPS con redirect HTTP→HTTPS. Reiniciar nginx:

```bash
docker compose restart nginx
```

Verificar:

```bash
curl -I https://sebasing.dev
```

La renovacion automatica la maneja el contenedor certbot cada 12 horas.

## 9. Correr migraciones y seed

```bash
# Migraciones de la base de datos
docker exec -it infra-nexus-crm-api-1 python -m alembic upgrade head

# Seed con datos demo
docker cp ~/nexus-crm-api/scripts infra-nexus-crm-api-1:/app/scripts
docker exec -it infra-nexus-crm-api-1 python -m scripts.seed
```

Credenciales demo: `demo@nexuscrm.dev` / `Demo1234!`

## 10. Seed de busqueda semantica

La API de busqueda semantica necesita documentos indexados para funcionar. El script sube los READMEs de cada proyecto como base de conocimiento:

```bash
# Copiar el script al contenedor
docker cp ~/semantic-search-api/scripts infra-search-api-1:/app/scripts

# Ejecutar el seed (borra documentos existentes y sube los READMEs)
docker exec -it infra-search-api-1 python -m scripts.seed-documents \
  --url http://localhost:8082
```

Tambien se puede ejecutar desde fuera del contenedor si tienes Python disponible:

```bash
cd ~/semantic-search-api
python scripts/seed-documents.py --url https://nexus-crm-semantic-search-api.sebasing.dev
```

El script es idempotente: limpia todos los documentos y los re-indexa desde cero.

## Actualizar un servicio

Cuando hay cambios en el codigo de un servicio:

```bash
# 1. Actualizar el codigo
cd ~/nexus-crm-api   # (o el repo que cambio)
git pull

# 2. Reconstruir la imagen
docker build -t ghcr.io/sebastianortiz/nexus-crm-api:latest .

# 3. Reiniciar el servicio
cd ~/infra
docker compose restart nexus-crm-api
```

Si solo cambio la configuracion de infra (docker-compose.yml, nginx configs):

```bash
cd ~/infra
git pull
docker compose down && docker compose up -d
```

## Actualizar solo Nginx (sin downtime de servicios)

```bash
cd ~/infra
git pull
docker compose restart nginx
```

## Ver logs de un servicio

```bash
cd ~/infra

# Logs en tiempo real
docker compose logs -f nexus-crm-api

# Ultimas 50 lineas
docker compose logs nexus-crm-api --tail 50

# Todos los servicios
docker compose logs --tail 20
```

## Troubleshooting

### Healthcheck falla (servicio unhealthy)

```bash
# Ver logs del servicio
docker compose logs <servicio> --tail 30

# Probar healthcheck manualmente
docker exec infra-<servicio>-1 wget --spider http://127.0.0.1:<puerto>/health
```

> Los healthchecks usan `127.0.0.1` (no `localhost`) porque Alpine resuelve localhost a IPv6 y los servicios escuchan en IPv4.

> Los servicios Python usan `python -c "import urllib.request; ..."` para healthcheck porque las imagenes slim no incluyen curl ni wget.

### Redis "too many colons in address"

Los servicios Go esperan `host:port` para Redis, no formato URL. En docker-compose.yml el `REDIS_URL` esta hardcodeado a `"redis:6379"` y `REDIS_PASSWORD` se pasa por separado.

### CORS "multiple values" error

Los headers CORS los manejan las aplicaciones (FastAPI CORSMiddleware, Go middleware), no Nginx. Si Nginx tambien agrega headers CORS, se duplican y el navegador los rechaza.

### ALLOWED_ORIGINS parsing error

La CRM API acepta `ALLOWED_ORIGINS` en formato comma-separated: `https://sebasing.dev,https://nexus-crm-dashboard.sebasing.dev`
