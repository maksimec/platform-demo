# Bookstore — Containerized Microservices Platform

A production-oriented bookstore application composed of multiple independent services orchestrated via Docker Compose. The stack includes a Node.js storefront, Python microservices, a PHP admin panel, automated HTTPS provisioning, and a host-level monitoring subsystem. Docker images are built and distributed via GitLab Container Registry through a shared CI/CD pipeline.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Repository Structure](#repository-structure)
- [Services](#services)
- [Infrastructure](#infrastructure)
- [Data Flow](#data-flow)
- [Configuration](#configuration)
- [Volumes](#volumes)
- [Deployment](#deployment)
- [CI/CD Pipeline](#cicd-pipeline)
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
      (nginx:alpine)
             │
             │  internal proxy
    ┌────────┴─────────────────────────────────┐
    │                                          │
    ▼                                          ▼
frontend (Node.js/Express)          admin-fpm (PHP-FPM 8.3)
    │
    ├── catalog-service (FastAPI / Python)
    │       └── PostgreSQL
    │
    ├── order-service (Node.js/Express)
    │       └── PostgreSQL
    │
    └── login-service (FastAPI / Python)
            └── PostgreSQL + Redis

Background:
    monitoring (Alpine 3.21 + supervisord)
        ├── disk_monitor_worker   [every 60 s]
        ├── ram_monitor_worker    [every 60 s]
        └── log_watcher           [continuous tail]

CI/CD:
    GitLab Container Registry
        └── registry.$REGISTRY_HOST
              ├── bookstore-maksimec/frontend
              ├── bookstore-maksimec/catalog-service
              ├── bookstore-maksimec/order-service
              ├── bookstore-maksimec/login-service
              └── bookstore-maksimec/admin
```

All external TLS termination is handled by `nginx-proxy`. Certificates are issued and renewed automatically by `acme-companion` via ACME HTTP-01 challenge without any manual steps.

---

## Repository Structure

```
bookstore/
├── catalog-service/          # FastAPI product catalogue (Python)
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
│   ├── .gitlab-ci.yml
│   └── Dockerfile
│
├── order-service/            # Express order management (Node.js)
│   ├── src/
│   │   ├── app.js
│   │   ├── db.js
│   │   └── routes/
│   │       └── orders.js
│   ├── package.json
│   ├── .gitlab-ci.yml
│   └── Dockerfile
│
├── login-service/            # FastAPI authentication (Python)
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
│   ├── .gitlab-ci.yml
│   └── Dockerfile
│
├── frontend/                 # Express + EJS storefront (Node.js)
│   ├── src/
│   │   ├── app.js
│   │   ├── routes/
│   │   │   ├── index.js
│   │   │   └── orders.js
│   │   └── views/
│   │       ├── layout.ejs
│   │       ├── index.ejs
│   │       ├── order.ejs
│   │       ├── confirmation.ejs
│   │       └── error.ejs
│   ├── package.json
│   ├── eslint.config.js
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
│   ├── .gitlab-ci.yml
│   └── Dockerfile
│
├── ci-templates/             # Shared GitLab CI/CD workflow templates
│   ├── node-service.yml
│   ├── python-service.yml
│   ├── php-service.yml
│   └── docker-build.yml
│
└── platform/                 # Infrastructure layer
    ├── docker-compose.yml
    ├── .env                  # Active secrets (git-ignored)
    ├── .env.example          # Template with placeholder values
    ├── db/
    │   └── init.sql          # PostgreSQL schema bootstrap
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
- **Responsibilities:** CRUD operations for books/products; reads from PostgreSQL; optional Redis caching via `cache.py`.
- **Build:** Python Alpine; pip install from `requirements.txt`.

### `order-service`

- **Runtime:** Node.js 20 + Express
- **Port (internal):** `$ORDER_PORT` (default: 5002)
- **Responsibilities:** Order creation and retrieval; writes to PostgreSQL via `db.js`.
- **Build:** Single-stage Node.js Alpine; `npm ci --omit=dev`.

### `login-service`

- **Runtime:** Python 3.12 + FastAPI + Uvicorn
- **Port (internal):** `$AUTH_PORT` (default: 5003)
- **Responsibilities:** User registration, login, and JWT issuance; session state backed by Redis; user records in PostgreSQL.
- **Build:** Python Alpine; pip install from `requirements.txt`.

### `admin-fpm`

- **Runtime:** PHP 8.3-FPM (Alpine)
- **Extensions:** `pdo`, `pdo_pgsql`, `mbstring`, `xml`
- **Responsibilities:** Server-side admin panel (product and order management); communicates with internal APIs; served by `bookstore-nginx` via FastCGI.
- **Build:** Alpine-based; `docker-php-ext-install`; `clear_env = no` in `www.conf`.

### `bookstore-nginx`

- **Image:** `nginx:alpine`
- **Responsibilities:** Internal reverse proxy and static file server. Routes `/api/catalog` → `catalog-service`, `/api/orders` → `order-service`, `/api/auth` → `login-service`, `/admin` → `admin-fpm` (FastCGI), `/` → `frontend`. Exposed to `nginx-proxy` via `VIRTUAL_HOST`.

### `postgres`

- **Image:** `postgres:16-alpine`
- **Responsibilities:** Single PostgreSQL instance shared by all services. Schema bootstrapped from `db/init.sql` on first start.
- **Persistence:** Named volume `db_data`.
- **Health check:** `pg_isready` — dependent services wait for healthy state before starting.

### `redis`

- **Image:** `redis:7-alpine`
- **Responsibilities:** Session cache for `login-service`; optional query cache for `catalog-service`.
- **Persistence:** Named volume `redis_data` (AOF enabled).

### `nginx-proxy`

- **Image:** `nginxproxy/nginx-proxy:1.6`
- **Responsibilities:** Automatic virtual host configuration driven by `VIRTUAL_HOST` labels on sibling containers. Terminates TLS on ports 80 and 443.

### `acme-companion`

- **Image:** `nginxproxy/acme-companion:2.4`
- **Responsibilities:** Monitors containers with `LETSENCRYPT_HOST` labels; requests and renews Let's Encrypt certificates automatically via HTTP-01 ACME challenge; writes certificates to the shared `nginx_certs` volume.

### `monitoring`

- **Base image:** `alpine:3.21`
- **Process manager:** `supervisord` (runs three processes — see [Monitoring](#monitoring))
- **Persistence:** Named volume `monitor_logs` mounted at `/var/log/monitor`.

---

## Infrastructure

### Networking

All services communicate over Docker's default bridge network created by Compose. No service ports are published to the host directly except `nginx-proxy` (80/443). Inter-service communication uses container names as DNS hostnames (e.g., `http://catalog-service:5001`).

### TLS / HTTPS

- `nginx-proxy` listens on 80 and 443 and dynamically generates upstream configurations.
- `acme-companion` issues a certificate per unique `LETSENCRYPT_HOST` value.
- Certificates are stored in the `nginx_certs` volume and reloaded automatically on renewal.
- No manual `certbot` or `nginx -s reload` commands are required.

### Host Filesystem Mounts (monitoring only)

| Container path | Host path | Mode |
|---|---|---|
| `/hostfs` | `/` | `ro` |
| `/host_proc` | `/proc` | `ro` |

These mounts allow monitoring scripts to report actual host disk and RAM usage rather than container-scoped values.

---

## Data Flow

```
Browser
  │
  ▼
nginx-proxy (443) ─── TLS termination ───► bookstore-nginx (80)
                                                   │
                          ┌───────────────┬────────┴───────────┬──────────────┐
                          ▼               ▼                    ▼              ▼
                      frontend      catalog-service      order-service   login-service
                          │               │                    │              │
                          └───────────────┴────────────────────┴──────────────┘
                                                   │
                                               postgres
                                               redis (auth + cache)

Admin panel:
Browser ──► nginx-proxy (443) ──► bookstore-nginx ──► admin-fpm (FastCGI 9000)
                                                           │
                                                       postgres (via PDO)
```

---

## Configuration

Copy `.env.example` to `.env` and populate all values before running the stack:

```bash
cp platform/.env.example platform/.env
```

### `.env` variables

| Variable | Used by | Description |
|---|---|---|
| `LETSENCRYPT_EMAIL` | `acme-companion` | Contact email for Let's Encrypt account registration |
| `BOOKSTORE_DOMAIN` | `nginx-proxy`, `acme-companion`, `bookstore-nginx` | Base domain for the storefront |
| `POSTGRES_DB` | `postgres`, all services | Database name |
| `POSTGRES_USER` | `postgres`, all services | Database superuser name |
| `POSTGRES_PASSWORD` | `postgres`, all services | Database superuser password |
| `JWT_SECRET` | `login-service`, `admin` | HS256 signing key (minimum 32 characters) |
| `JWT_ALGORITHM` | `login-service`, `admin` | JWT algorithm — `HS256` recommended |
| `SESSION_SECRET` | `admin` | Session cookie signing secret (minimum 32 characters) |
| `FRONTEND_PORT` | `frontend`, `bookstore-nginx` | Internal port for the Node.js frontend |
| `CATALOG_PORT` | `catalog-service`, `bookstore-nginx` | Internal port for the FastAPI catalogue |
| `ORDER_PORT` | `order-service`, `bookstore-nginx` | Internal port for the Express order API |
| `AUTH_PORT` | `login-service`, `bookstore-nginx` | Internal port for the FastAPI auth service |
| `REGISTRY_HOST` | CI/CD pipeline, `docker compose pull` | GitLab Container Registry hostname (e.g., `registry.gitlab.com`) |
| `REGISTRY_USERNAME` | CI/CD pipeline, `docker login` | GitLab registry username or deploy token name |
| `REGISTRY_PASSWORD` | CI/CD pipeline, `docker login` | GitLab registry password or deploy token secret |

---

## Volumes

| Volume | Service | Purpose |
|---|---|---|
| `db_data` | `postgres` | PostgreSQL data directory |
| `redis_data` | `redis` | Redis AOF persistence |
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
- GitLab Container Registry credentials available (required to pull pre-built images).

### Steps

```bash
# 1. Clone the repository
git clone <repository-url> bookstore
cd bookstore/platform

# 2. Create the environment file
cp .env.example .env
# Edit .env — fill in all required values

# 3. Authenticate with GitLab Container Registry
docker login $REGISTRY_HOST \
  -u "$REGISTRY_USERNAME" \
  -p "$REGISTRY_PASSWORD"

# 4. Pull pre-built images and start the stack
docker compose pull
docker compose up -d

# 5. Verify all services are healthy
docker compose ps
```

### Health checks

```bash
# PostgreSQL
docker exec bookstore-postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"

# Service healthcheck states (all should be "healthy")
docker inspect --format='{{.Name}} → {{.State.Health.Status}}' \
  $(docker compose ps -q)

# Monitoring logs
docker exec monitoring ls -lh /var/log/monitor

# ACME certificate issuance (wait ~60 s after first start)
docker logs nginx-proxy-acme | grep "Certificate"
```

### Teardown

```bash
# Stop and remove containers (preserves volumes)
docker compose down

# Stop and remove containers + all named volumes (destructive)
docker compose down -v
```

---

## CI/CD Pipeline

Each application service (`frontend`, `order-service`, `catalog-service`, `login-service`, `admin`) has a `.gitlab-ci.yml` that inherits shared jobs from the `bookstore-maksimec/ci-templates` repository. Every push triggers a Quality Gate; only passing pipelines produce and publish a Docker image.

### Pipeline Stages

| Stage | Tool(s) | Service |
|---|---|---|
| `lint` | `eslint` (Node.js), `ruff` (Python), `phpcs` (PHP) | All |
| `analysis` | `mypy` (Python), `phpstan` + `psalm` (PHP) | Python, PHP |
| `security` | `npm audit`, `pip-audit`, `composer audit` | All |
| `test` | `jest` (Node.js), `pytest` (Python) | Node.js, Python |
| `health-check` | Container started ephemerally; `/health` endpoint polled | All |
| `build` | `docker build` + `docker push` → GitLab Registry | `main` branch only |

### Shared Templates (`ci-templates/`)

| File | Consumed by |
|---|---|
| `node-service.yml` | `frontend`, `order-service` |
| `python-service.yml` | `catalog-service`, `login-service` |
| `php-service.yml` | `admin` |
| `docker-build.yml` | All services (build stage) |

### Image Naming Convention

```
registry.gitlab.com/bookstore-maksimec/<service>:<git-sha>
registry.gitlab.com/bookstore-maksimec/<service>:latest   # main branch only
```

---

## Monitoring

The `monitoring` container runs three concurrent processes under `supervisord`:

| Process | Script | Mode | Threshold |
|---|---|---|---|
| `disk_monitor_worker` | `disk_monitor.sh` | Loop with 60 s sleep | 80% host disk usage |
| `ram_monitor_worker` | `ram_monitor.sh` | Loop with 60 s sleep | 85% host RAM usage |
| `log_watcher` | `log_watcher.sh` | Continuous `tail -F` | — |

### Log files

All logs are written to the `monitor_logs` named volume:

| File | Content |
|---|---|
| `/var/log/monitor/disk_monitor.log` | Timestamped warnings when disk usage exceeds threshold |
| `/var/log/monitor/ram_monitor.log` | Timestamped warnings when RAM usage exceeds threshold |
| `/var/log/monitor/email_notifications.log` | Aggregated warning events detected by `log_watcher` |

### How scripts read host metrics

- **Disk:** `disk_monitor.sh` runs `df -P /hostfs` where `/hostfs` is the host root (`/`) bind-mounted read-only.
- **RAM:** `ram_monitor.sh` reads `/host_proc/meminfo` where `/host_proc` is the host `/proc` bind-mounted read-only, ensuring container memory limits do not affect reported values.

### Viewing logs

```bash
docker compose exec monitoring tail -f /var/log/monitor/disk_monitor.log
docker compose exec monitoring tail -f /var/log/monitor/ram_monitor.log
docker compose exec monitoring tail -f /var/log/monitor/email_notifications.log
```

### supervisord status

```bash
docker compose exec monitoring supervisorctl status
```

Expected output:

```
disk_monitor_worker     RUNNING   pid ..., uptime ...
log_watcher             RUNNING   pid ..., uptime ...
ram_monitor_worker      RUNNING   pid ..., uptime ...
```

