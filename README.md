# sebasing-infra

Repositorio de infraestructura para el ecosistema **sebasing.dev**. Orquesta todos los servicios del portafolio profesional en un servidor Hetzner usando Docker Compose y Nginx como reverse proxy.

## Arquitectura

```
                    Internet
                       |
                   [ Nginx ]
                   :80 / :443
                       |
       +-------+-------+--------+--------+
       |       |        |        |        |
  sebasing  crm-api  crm-dash  events  search
   :3000    :8000      :80     :8081    :8082
       |       |        |        |        |
       +-------+--------+--------+--------+
               |                 |
          [ PostgreSQL ]    [ Redis ]
             :5432            :6379
               |
          [ ChromaDB ]
             :8000
```

### Servicios de aplicacion

| Servicio | Subdominio | Puerto | Stack |
|---|---|---|---|
| `portfolio-web` | sebasing.dev | 3000 | Next.js |
| `nexus-crm-api` | nexus-crm-api.sebasing.dev | 8000 | FastAPI |
| `nexus-crm-dashboard` | nexus-crm-dashboard.sebasing.dev | 80 | Angular |
| `event-api` | nexus-crm-events-api.sebasing.dev | 8081 | Go |
| `event-workers` | (interno) | - | Go |
| `search-api` | nexus-crm-semantic-search-api.sebasing.dev | 8082 | FastAPI |

### Infraestructura

| Servicio | Puerto interno | Descripcion |
|---|---|---|
| PostgreSQL 16 | 5432 | Base de datos (schemas: crm, events, search) |
| Redis 7 | 6379 | Cache + streams de eventos |
| ChromaDB | 8000 | Vector store para busqueda semantica |
| Nginx | 80/443 | Reverse proxy + SSL |
| Certbot | - | Renovacion automatica de certificados |

## Requisitos previos

- Servidor Ubuntu 24.04 LTS (Hetzner VPS recomendado)
- Dominio `sebasing.dev` con DNS apuntando al servidor
- Cuenta de GitHub con acceso a las imagenes en `ghcr.io`

## Configuracion de un servidor nuevo

```bash
# 1. Ejecutar el script de setup como root
sudo bash scripts/setup-server.sh

# 2. Configurar variables de entorno
nano /opt/sebasing/.env

# 3. Autenticarse en GitHub Container Registry
docker login ghcr.io -u <usuario> -p <token>

# 4. Generar certificados SSL (ver seccion SSL)

# 5. Desplegar
cd /opt/sebasing
./scripts/deploy.sh
```

## Deploy

### Todos los servicios

```bash
./scripts/deploy.sh
```

Descarga las imagenes mas recientes, reinicia todos los servicios y verifica su salud.

### Un solo servicio

```bash
./scripts/deploy-service.sh <nombre-servicio>

# Ejemplo:
./scripts/deploy-service.sh nexus-crm-api
```

Servicios disponibles: `portfolio-web`, `nexus-crm-api`, `nexus-crm-dashboard`, `event-api`, `event-workers`, `search-api`.

### Deploy automatico (CI/CD)

El workflow de GitHub Actions (`.github/workflows/deploy.yml`) se ejecuta automaticamente al hacer push a `main`. Requiere configurar estos secretos en el repositorio:

| Secreto | Descripcion |
|---|---|
| `SERVER_HOST` | IP o hostname del servidor Hetzner |
| `SERVER_USER` | Usuario SSH (por defecto: `deploy`) |
| `SERVER_SSH_KEY` | Clave privada SSH para el usuario deploy |

## Desarrollo local

Para levantar solo la infraestructura (postgres, redis, chromadb) en desarrollo:

```bash
docker compose -f docker-compose.dev.yml up -d
```

Los servicios de aplicacion se ejecutan directamente en la maquina del desarrollador. Puertos disponibles:

- PostgreSQL: `localhost:5432` (user: postgres, pass: postgres, db: sebasing)
- Redis: `localhost:6379` (sin password)
- ChromaDB: `localhost:8000`

## Backup de base de datos

```bash
# Ejecutar manualmente
./scripts/backup-db.sh

# Configurar en crontab (todos los dias a las 3am)
crontab -e
# Agregar: 0 3 * * * /opt/sebasing/scripts/backup-db.sh >> /opt/sebasing/backups/backup.log 2>&1
```

Los backups se guardan en `backups/` con rotacion automatica de 7 dias.

## SSL con Certbot

### Configuracion inicial

1. Asegurarse de que los DNS apunten al servidor.
2. Generar certificados (con nginx detenido):

```bash
docker compose down nginx

certbot certonly --standalone \
  -d sebasing.dev \
  -d www.sebasing.dev \
  -d nexus-crm-api.sebasing.dev \
  -d nexus-crm-dashboard.sebasing.dev \
  -d nexus-crm-events-api.sebasing.dev \
  -d nexus-crm-semantic-search-api.sebasing.dev

# Copiar certificados al directorio esperado
cp -rL /etc/letsencrypt/live ssl/certbot/conf/
cp -rL /etc/letsencrypt/archive ssl/certbot/conf/
```

3. Descomentar los bloques SSL en los archivos `nginx/conf.d/*.conf`.
4. Reiniciar nginx: `docker compose up -d nginx`

### Renovacion automatica

El servicio `certbot` en docker-compose.yml se encarga de renovar los certificados cada 12 horas. Solo se renuevan si estan proximos a expirar.

## Variables de entorno

Ver `.env.example` para la referencia completa. Variables principales:

| Variable | Descripcion |
|---|---|
| `POSTGRES_USER` | Usuario de PostgreSQL |
| `POSTGRES_PASSWORD` | Password de PostgreSQL |
| `POSTGRES_DB` | Nombre de la base de datos |
| `DATABASE_URL` | URL completa de conexion a PostgreSQL |
| `REDIS_PASSWORD` | Password de Redis |
| `REDIS_URL` | URL completa de conexion a Redis |
| `JWT_SECRET_KEY` | Secreto para firmar tokens JWT |
| `EVENT_SERVICE_API_KEY` | API key para comunicacion interna con el servicio de eventos |
| `ALLOWED_ORIGINS` | Origenes CORS permitidos (separados por coma) |

## Estructura del repositorio

```
sebasing-infra/
├── .github/workflows/
│   └── deploy.yml              # CI/CD: deploy automatico
├── nginx/
│   ├── nginx.conf              # Configuracion principal de Nginx
│   └── conf.d/
│       ├── portfolio.conf      # sebasing.dev
│       ├── crm-api.conf        # nexus-crm-api.sebasing.dev
│       ├── crm-dashboard.conf  # nexus-crm-dashboard.sebasing.dev
│       ├── events.conf         # nexus-crm-events-api.sebasing.dev
│       └── search.conf         # nexus-crm-semantic-search-api.sebasing.dev
├── scripts/
│   ├── setup-server.sh         # Configuracion inicial del servidor
│   ├── deploy.sh               # Deploy de todos los servicios
│   ├── deploy-service.sh       # Deploy de un servicio individual
│   ├── backup-db.sh            # Backup de PostgreSQL
│   └── init-db.sql             # Inicializacion de schemas
├── docker-compose.yml          # Produccion
├── docker-compose.dev.yml      # Desarrollo local (solo infra)
├── .env.example                # Variables de entorno de referencia
├── .gitignore
└── README.md
```
