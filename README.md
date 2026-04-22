# AtoM-Docker

Access to Memory (AtoM) containerized with Docker Compose for local testing, server deployments, and optional S3-backed uploads.

## Description

This repository packages AtoM and its required services into a reproducible Docker stack. The default setup includes:

- AtoM application container (`atom`)
- One-time initialization container (`atom_init`)
- Percona database (`db`)
- Memcached (`cache`)
- Elasticsearch (`elasticsearch`)
- Gearman (`gearmand`)

The app container initializes AtoM through environment variables in `.env`, including site metadata and admin account defaults.

## Features

- Single-command startup with Docker Compose
- Automatic first-run initialization via `atom_init`
- Persistent named volumes for database, search index, uploads, and cache
- Environment-driven configuration through `.env`
- Optional Adminer for development (`docker-compose.dev.yml`)
- Optional S3 uploads mount through `s3fs` (`docker-compose.s3.yml`)

## Pre-requisites

- Docker Engine and Docker Compose plugin (`docker compose`)
- Linux host recommended for S3/FUSE mode (`/dev/fuse`, `SYS_ADMIN`, shared mounts)
- At least 4 GB RAM available for the full stack (Elasticsearch + DB + PHP)
- A copy of the environment file:

```bash
cp .env.example .env
```

Before deploying, review and set at minimum:

- `MYSQL_ROOT_PASSWORD`, `MYSQL_USER`, `MYSQL_PASSWORD`
- `ATOM_ADMIN_USERNAME`, `ATOM_ADMIN_EMAIL`, `ATOM_ADMIN_PASSWORD`
- `ATOM_SITE_BASE_URL`
- `ATOM_PORT` (if `8080` is not suitable)

## Deployment

### Quick-start

Use this for local evaluation with default stack behavior.

```bash
cp .env.example .env
docker compose up -d
```

Then open AtoM at:

- `http://127.0.0.1:${ATOM_PORT}` (default `http://127.0.0.1:8080`)

Optional (development DB UI with Adminer on `8081`):

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

To follow logs:

```bash
docker compose logs -f atom atom_init
```

### Production

Use the base compose file and hardened environment values.

1. Copy and edit environment:

```bash
cp .env.example .env
```

2. Set strong credentials and production values in `.env`:

- Database passwords and app admin password
- Public `ATOM_SITE_BASE_URL` (for example, `https://archives.example.org`)
- Appropriate sizing (for example `MYSQL_INNODB_BUFFER_POOL_SIZE`, `ES_JAVA_OPTS`, PHP limits)

3. Start services:

```bash
docker compose up -d
```

4. Validate service health:

```bash
docker compose ps
docker compose logs --tail=200 atom atom_init db elasticsearch
```

Notes:

- `atom_init` runs installation tasks and exits once complete.
- Data persists in named Docker volumes; backups should include DB and uploads.
- Do not keep the example credentials from `.env.example` in production.

### Using S3 for uploads

This mode mounts an S3 bucket into `/atom/src/uploads` via `s3fs` and the `docker-compose.s3.yml` override.

At container startup, `docker/entrypoint.sh` selects the nginx config based on `USE_S3FS`:

- `USE_S3FS=true` enables the S3-aware config in `docker/etc/nginx/nginx-s3fs.conf`
- `USE_S3FS=false` (or unset) keeps the default config in `docker/etc/nginx/nginx-default.conf`

1. Ensure host support:

- `/mnt/s3bucket` exists on the host
- `/dev/fuse` is available
- Container runtime allows `SYS_ADMIN` and `apparmor:unconfined`

2. Configure S3 variables in `.env`:
- `USE_S3FS` set to `true`
- `AWS_S3_BUCKET`
- `AWS_S3_ACCESS_KEY_ID`
- `AWS_S3_SECRET_ACCESS_KEY`
- `AWS_S3_URL`
- `ATOM_STATIC_URL` as a concrete absolute URL for your static host, for example `https://cdn.example.com` or `https://cdn.example.com/static`
- Optional: `S3FS_ARGS`, `S3FS_DEBUG`

`ATOM_STATIC_URL` is also used to render the nginx S3 proxy target at startup. For that reason it must be:

- an absolute `http://` or `https://` URL
- a concrete host name, not a wildcard such as `https://*.example.com`
- free of query strings, fragments, and embedded credentials

If you include a path prefix, nginx will preserve it when proxying `/uploads/r/*` requests.

3. Start with compose override:

```bash
docker compose -f docker-compose.yml -f docker-compose.s3.yml up -d
```

4. Confirm the `s3fs` service is running and mounts are healthy:

```bash
docker compose -f docker-compose.yml -f docker-compose.s3.yml ps
docker compose -f docker-compose.yml -f docker-compose.s3.yml logs --tail=200 s3fs atom
```

If the S3 mount is unavailable, AtoM uploads may fail because `/atom/src/uploads` is mapped to the mounted bucket path in S3 mode.
