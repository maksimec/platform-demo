# Bookstore — Containerized Microservices Platform

A production-oriented bookstore application composed of multiple independent services orchestrated via Docker Compose. The stack includes a Node.js storefront, Python microservices, a PHP admin panel, automated HTTPS provisioning, a private Docker registry, and a host-level monitoring subsystem. All service images are built and published via GitLab CI/CD pipelines and pulled from a private registry at runtime.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Repository Structure](#repository-structure)
- [Services](#services)
- [Infrastructure](#infrastructure)
- [CI/CD](#cicd)
- [Data Flow](#data-flow)
- [Configuration](#configuration)
- [Volumes](#volumes)
- [Deployment](#deployment)
- [Monitoring](#monitoring)

---

## Architecture Overview

```
Internet
    │
    ▼
┌─────────────────────────────────┐
│        nginx-proxy (80/443)     │  ← nginxproxy/nginx-proxy:1.6
│   + acme-companion (Let's Enc.) │  ← nginxproxy/acme-companion:2.4
└────────────┬────────────────────┘
             │  routes by VIRTUAL_HOST
             ▼
      bookstore-nginx
      (nginx:1.30-alpine)
             │
             │  internal proxy / FastCGI
             ├──────────────────────────────────────────┐
             │                                          │
             ▼                                          ▼
  frontend (Node.js/Express)              admin-fpm (PHP-FPM 8.3)
             │
             ├── catalog-service (FastAPI / Python 3.12)
             │         └── PostgreSQL 16
             │
             ├── order-service (Node.js/Express)
             │         └── PostgreSQL 16
             │
             └── login-service (FastAPI / Python 3.12)
                       └── PostgreSQL 16

Background:
    monitoring (Alpine + supervisord)
        ├── disk_monitor_worker   [every 60 s]
        ├── ram_monitor_worker    [every 60 s]
        └── log_watcher           [continuous tail]
```

All external TLS termination is handled by `nginx-proxy`. Certificates are issued and renewed automatically by `acme-companion` via ACME HTTP-01 challenge.

---

## Repository Structure

```
bookstore/
├── catalog-service/          # FastAPI product catalogue (Python 3.12)
│   ├── app/
│   │   ├── main.py
│   │   ├── models.py
│   │   ├── schemas.py
│   │   ├── database.py
│   │   ├── cache.py
│   │   ├── config.py
│   │   ├── logging_config.py
│   │   └── routes/
│   │       └── catalog.py
│   ├── requirements.txt
│   ├── .dockerignore
│   ├── .gitlab-ci.yml
│   └── Dockerfile
│
├── order-service/            # Express order management (Node.js 20)
│   ├── src/
│   │   ├── app.js
│   │   ├── db.js
│   │   └── routes/
│   │       └── orders.js
│   ├── package.json
│   ├── .dockerignore
│   ├── .gitlab-ci.yml
│   └── Dockerfile
│
├── login-service/            # FastAPI authentication (Python 3.12)
│   ├── app/
│   │   ├── main.py
│   │   ├── models.py
│   │   ├── schemas.py
│   │   ├── database.py
│   │   ├── config.py
│   │   ├── logging_config.py
│   │   └── routes/
│   │       └── auth.py
│   ├── requirements.txt
│   ├── .dockerignore
│   ├── .gitlab-ci.yml
│   └── Dockerfile
│
├── frontend/                 # Express + EJS storefront (Node.js 20)
│   ├── src/
│   │   ├── app.js
│   │   └── routes/
│   │       ├── index.js
│   │       └── orders.js
│   │   └── views/
│   │       ├── layout.ejs
│   │       ├── index.ejs
│   │       ├── order.ejs
│   │       ├── confirmation.ejs
│   │       └── error.ejs
│   ├── package.json
│   ├── .dockerignore
│   ├── .gitlab-ci.yml
│   └── Dockerfile
│
├── admin/                    # PHP 8.3 admin panel
│   ├── public/
│   │   ├── index.php
│   │   ├── login.php
│   │   ├── logout.php
│   │   ├── orders.php
│   │   ├── products.php
│   │   └── includes/
│   │       ├── api.php
│   │       ├── auth.php
│   │       └── config.php
│   ├── .dockerignore
│   ├── .gitlab-ci.yml
│   └── Dockerfile
│
└── platform/                 # Infrastructure layer
    ├── docker-compose.yml
    ├── docker-compose.ci.yml # CI port-override for integration tests
    ├── .env                  # Active secrets (git-ignored)
    ├── .env.example          # Template with placeholder values
    ├── .dockerignore
    ├── .gitlab-ci.yml        # validate / build-monitoring / integration
    ├── db/
    │   └── init.sql          # PostgreSQL schema + seed data
    ├── nginx/
    │   └── bookstore.conf    # Internal reverse proxy config
    └── monitoring/
        ├── Dockerfile
        ├── supervisord.conf
        ├── disk_monitor.sh
        ├── ram_monitor.sh
        ├── log_watcher.sh
        ├── disk_monitor_worker.sh
        └── ram_monitor_worker.sh
```

---

## Services

### `frontend`

- **Runtime:** Node.js 20 + Express + EJS
- **Port (internal):** `$FRONTEND_PORT` (default: 3000)
- **Responsibilities:** Renders product catalogue and order pages; communicates with `catalog-service` and `order-service` over Docker's internal network.
- **Build:** Single-stage Node.js Alpine; `npm ci --omit=dev`.

### `catalog-service`

- **Runtime:** Python 3.12 + FastAPI + Uvicorn
- **Port (internal):** `$CATALOG_PORT` (default: 5001)
- **Responsibilities:** CRUD operations for books; reads from PostgreSQL; optional Redis caching controlled by `REDIS_ENABLED` environment variable.
- **Build:** Python Alpine; pip install from `requirements.txt`.

### `order-service`

- **Runtime:** Node.js 20 + Express
- **Port (internal):** `$ORDER_PORT` (default: 5002)
- **Responsibilities:** Order creation and retrieval; writes to PostgreSQL via `db.js`.
- **Build:** Single-stage Node.js Alpine; `npm ci --omit=dev`.

### `login-service`

- **Runtime:** Python 3.12 + FastAPI + Uvicorn
- **Port (internal):** `$AUTH_PORT` (default: 5003)
- **Responsibilities:** User registration, login, and JWT issuance; user records in PostgreSQL.
- **Build:** Python Alpine; pip install from `requirements.txt`.

### `admin-fpm`

- **Runtime:** PHP 8.3-FPM (Alpine)
- **Extensions:** `pdo`, `pdo_pgsql`, `mbstring`, `xml`
- **Responsibilities:** Server-side admin panel for product and order management; communicates with internal APIs; served by `bookstore-nginx` via FastCGI.
- **Build:** `COPY public/ /var/www/admin/`; `docker-php-ext-install`; `clear_env = no` in `www.conf`.
- **Volume handoff:** On startup, copies `/var/www/admin/` into the shared `admin_public` volume so `bookstore-nginx` can serve static assets without a direct bind mount.

### `bookstore-nginx`

- **Image:** `nginx:1.30-alpine`
- **Responsibilities:** Internal reverse proxy and static file server. Routes:
  - `/api/catalog/` → `catalog-service`
  - `/api/orders/` → `order-service`
  - `/api/auth/` → `login-service`
  - `/admin` → `admin-fpm` via FastCGI (port 9000)
  - `/` → `frontend`
- Exposed to `nginx-proxy` via `VIRTUAL_HOST` environment variable.

### `postgres`

- **Image:** `postgres:16-alpine`
- **Responsibilities:** Single PostgreSQL instance shared by all services. Schema and seed data bootstrapped from `db/init.sql` on first start.
- **Persistence:** Named volume `db_data`.
- **Health check:** `pg_isready` — all dependent services wait for `service_healthy` before starting.

### `redis`

- **Image:** `redis:7-alpine`
- **Responsibilities:** Optional query cache for `catalog-service`.
- **Health check:** `redis-cli ping | grep PONG`.

### `nginx-proxy`

- **Image:** `nginxproxy/nginx-proxy:1.6`
- **Responsibilities:** Automatic virtual host configuration driven by `VIRTUAL_HOST` environment variables on sibling containers. Terminates TLS on ports 80 and 443.

### `acme-companion`

- **Image:** `nginxproxy/acme-companion:2.4`
- **Responsibilities:** Requests and renews Let's Encrypt certificates automatically via HTTP-01 ACME challenge; writes certificates to the shared `nginx_certs` volume.

### `monitoring`

- **Base image:** `alpine:latest`
- **Process manager:** `supervisord`
- **Persistence:** Named volume `monitor_logs` at `/var/log/monitor`.
- **Host mounts:** `/` → `/hostfs:ro`, `/proc` → `/host_proc:ro`.

---

## Infrastructure

### Networking

All services communicate over Docker's default bridge network created by Compose. No service ports are published to the host directly except `nginx-proxy` (80/443). Inter-service communication uses container names as DNS hostnames (e.g., `http://catalog-service:5001`).

### TLS / HTTPS

- `nginx-proxy` listens on 80 and 443 and dynamically generates upstream configurations from running containers.
- `acme-companion` issues one certificate per unique `LETSENCRYPT_HOST` value.
- Certificates are stored in the `nginx_certs` volume and reloaded automatically on renewal.

### Host Filesystem Mounts (monitoring only)

| Container path | Host path | Mode |
|---|---|---|
| `/hostfs` | `/` | `ro` |
| `/host_proc` | `/proc` | `ro` |

These mounts allow monitoring scripts to report actual host disk and RAM usage rather than container-scoped values.

---

## CI/CD

Each service repository contains an independent `.gitlab-ci.yml` pipeline. The `platform` repository contains the infrastructure pipeline.

### Per-service pipelines

| Stage | Job | Description |
|---|---|---|
| `lint` | `ruff check` / `eslint` | Static analysis and code style enforcement |
| `build` | `docker build` + `docker push` | Build image, tag with `$CI_COMMIT_SHORT_SHA` and `latest`, push to private registry |

### Platform pipeline (`platform/.gitlab-ci.yml`)

| Stage | Job | Description |
|---|---|---|
| `validate` | `validate-compose` | Runs `docker compose config` against `.env.example` to verify the Compose file is syntactically valid |
| `build` | `build-monitoring` | Builds and pushes the `monitoring` image on commits to `main` |
| `integration` | `integration` | Pulls all service images from the private registry, starts the full stack via `docker-compose.ci.yml` override (adds `ports:` bindings), waits for all `/health` endpoints to respond, then tears down |

### Integration test port mapping

`docker-compose.ci.yml` extends `docker-compose.yml` by adding `ports:` bindings so the GitLab Runner can reach services via `http://docker:<port>/health`:

```yaml
services:
  catalog-service:
    ports:
      - "${CATALOG_PORT}:${CATALOG_PORT}"
  order-service:
    ports:
      - "${ORDER_PORT}:${ORDER_PORT}"
  login-service:
    ports:
      - "${AUTH_PORT}:${AUTH_PORT}"
  frontend:
    ports:
      - "${FRONTEND_PORT}:${FRONTEND_PORT}"
```

### Required CI/CD variables

Set the following variables in each GitLab project under **Settings → CI/CD → Variables**:

| Variable | Description |
|---|---|
| `REGISTRY_HOST` | Hostname of the private Docker registry (e.g. `registry.example.com`) |
| `REGISTRY_USER` | Registry login username |
| `REGISTRY_PASSWORD` | Registry login password |

---

## Data Flow

```
Browser
  │
  ▼
nginx-proxy (443) ── TLS termination ──► bookstore-nginx (80)
                                                  │
                         ┌──────────────┬─────────┴──────────┬──────────────┐
                         ▼              ▼                     ▼              ▼
                     frontend    catalog-service        order-service  login-service
                         │              │                     │              │
                         └──────────────┴─────────────────────┴──────────────┘
                                                  │
                                              postgres
                                              redis (optional cache)

Admin panel:
Browser ──► nginx-proxy (443) ──► bookstore-nginx ──► admin-fpm (FastCGI 9000)
                                                            │
                                                        postgres (via PDO)
```

---

## Configuration

Copy `.env.example` to `.env` and populate all values before running the stack:

```bash
cp .env.example .env
```

### `.env` variables

| Variable | Used by | Description |
|---|---|---|
| `LETSENCRYPT_EMAIL` | `acme-companion` | Contact email for Let's Encrypt account registration |
| `BOOKSTORE_DOMAIN` | `nginx-proxy`, `bookstore-nginx` | Public domain name for the storefront |
| `POSTGRES_DB` | `postgres`, all services | Database name |
| `POSTGRES_USER` | `postgres`, all services | Database username |
| `POSTGRES_PASSWORD` | `postgres`, all services | Database password |
| `JWT_SECRET` | `login-service`, `admin-fpm` | HS256 signing key (minimum 32 characters) |
| `JWT_ALGORITHM` | `login-service`, `admin-fpm` | JWT algorithm — `HS256` recommended |
| `SESSION_SECRET` | `admin-fpm` | Session cookie signing secret |
| `FRONTEND_PORT` | `frontend`, `bookstore-nginx` | Internal port for the Node.js frontend (default: 3000) |
| `CATALOG_PORT` | `catalog-service`, `bookstore-nginx` | Internal port for the FastAPI catalogue (default: 5001) |
| `ORDER_PORT` | `order-service`, `bookstore-nginx` | Internal port for the Express order API (default: 5002) |
| `AUTH_PORT` | `login-service`, `bookstore-nginx` | Internal port for the FastAPI auth service (default: 5003) |
| `REGISTRY_HOST` | all services | Hostname of the private Docker registry |

---

## Volumes

| Volume | Service | Purpose |
|---|---|---|
| `db_data` | `postgres` | PostgreSQL data directory |
| `admin_public` | `admin-fpm`, `bookstore-nginx` | Static PHP assets copied from image on startup |
| `monitor_logs` | `monitoring` | Log files: `disk_monitor.log`, `ram_monitor.log`, `email_notifications.log` |
| `nginx_conf` | `nginx-proxy` | Generated virtual host configurations |
| `nginx_vhost` | `nginx-proxy` | Per-host overrides |
| `nginx_html` | `nginx-proxy`, `acme-companion` | ACME HTTP-01 challenge files |
| `nginx_certs` | `nginx-proxy`, `acme-companion` | TLS certificates and private keys |
| `acme` | `acme-companion` | ACME account data |

---

## Deployment

### Prerequisites

- Docker Engine 24+ with the Compose plugin installed.
- DNS `A` record for `$BOOKSTORE_DOMAIN` pointing to the host's public IP.
- Ports 80 and 443 open in the host firewall / security group.
- All service images built and pushed to the private registry via CI/CD pipelines.

### Steps

```bash
# 1. Clone the platform repository
git clone <repository-url> platform
cd platform

# 2. Create the environment file
cp .env.example .env
# Edit .env — fill in all required values

# 3. Start the stack
docker compose up -d

# 4. Verify all services are running
docker compose ps -a
```

### Health checks

```bash
# All containers status
docker compose ps -a

# PostgreSQL
docker exec bookstore-postgres pg_isready -U $POSTGRES_USER -d $POSTGRES_DB

# Individual service health endpoints
curl http://localhost/api/catalog/health
curl http://localhost/api/orders/health
curl http://localhost/api/auth/health

# ACME certificate issuance (wait ~60 s after first start)
docker logs nginx-proxy-acme | grep "Certificate"
```

### Updating a service image

```bash
# Pull the latest image and recreate only the affected container
docker compose pull catalog-service
docker compose up -d --no-deps catalog-service
```

### Teardown

```bash
# Stop and remove containers (preserves volumes)
docker compose down

# Stop and remove containers + all named volumes (destructive)
docker compose down -v
```

---

## Monitoring

The `monitoring` container runs three concurrent processes under `supervisord`:

| Process | Script | Mode | Threshold |
|---|---|---|---|
| `disk_monitor_worker` | `disk_monitor.sh` | Loop, 60 s interval | 80% host disk usage |
| `ram_monitor_worker` | `ram_monitor.sh` | Loop, 60 s interval | 85% host RAM usage |
| `log_watcher` | `log_watcher.sh` | Continuous `tail -F` | — |

### Log files

All logs are written to the `monitor_logs` named volume:

| File | Content |
|---|---|
| `/var/log/monitor/disk_monitor.log` | Timestamped warnings when disk usage exceeds 80% |
| `/var/log/monitor/ram_monitor.log` | Timestamped warnings when RAM usage exceeds 85% |
| `/var/log/monitor/email_notifications.log` | Aggregated warning events detected by `log_watcher` |

### How scripts read host metrics

- **Disk:** `disk_monitor.sh` runs `df -P /hostfs` where `/hostfs` is the host root (`/`) bind-mounted read-only.
- **RAM:** `ram_monitor.sh` reads `/host_proc/meminfo` where `/host_proc` is the host `/proc` bind-mounted read-only, ensuring container memory limits do not affect reported values.

### Viewing logs

```bash
docker exec monitoring tail -f /var/log/monitor/disk_monitor.log
docker exec monitoring tail -f /var/log/monitor/ram_monitor.log
docker exec monitoring tail -f /var/log/monitor/email_notifications.log
```

### supervisord status

```bash
docker exec monitoring supervisorctl status
```

Expected output:

```
disk_monitor_worker     RUNNING   pid ..., uptime ...
log_watcher             RUNNING   pid ..., uptime ...
ram_monitor_worker      RUNNING   pid ..., uptime ...
```

