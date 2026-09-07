# Maintainer guide

## Local build and release gate

Docker Desktop or Docker Engine with Compose v2 is required. The integration
script builds all three images and then exercises the same workflow students
use:

```bash
tests/run_integration.sh
```

It verifies clean PostgreSQL initialization, exact dataset row counts,
extensions and materialized views, Python 3.14 and all course imports,
SQLAlchemy and Psycopg connections, sample-notebook execution, both browser
endpoints, pgAdmin's registered connection, restricted privileges, non-root
service processes, persistence, and explicit reset behavior.

For a local development stack outside the test harness:

```bash
docker compose --file compose.yaml --file compose.dev.yaml build --pull
docker compose --file compose.yaml --file compose.dev.yaml up --detach --wait
```

Run the configuration check after any Compose change:

```bash
docker compose --file compose.yaml --file compose.dev.yaml config --quiet
```

## Architecture support

The base-image references in each Dockerfile are pinned to multi-platform index
digests. Do not replace them with an architecture-specific child digest. The
ordinary CI workflow runs `tests/run_integration.sh` natively on both
`ubuntu-24.04` (AMD64) and `ubuntu-24.04-arm` (ARM64).

The manual publication workflow repeats both native tests before it is allowed
to build and push manifests for `linux/amd64,linux/arm64`. It publishes:

- `ghcr.io/tamu-stat315/course-db-seed`
- `ghcr.io/tamu-stat315/course-notebook`
- `ghcr.io/tamu-stat315/pgadmin4-mirror`

It also attaches BuildKit provenance and SBOM attestations and rejects release
tags that do not follow the `2026-fall.1` pattern. Make each GHCR package public
after its first publication so students can pull without authentication.

## Updating Python

Edit `pynb_image/pyproject.toml`, then regenerate the lock with the exact uv
version pinned in `pynb_image/Dockerfile`. If the minimal uv image cannot
discover libc on the current host, copy `/uv` from that image into the pinned
Python base image and run `uv lock --upgrade` there. The committed lock requires
wheels for Linux x86-64 and AArch64; both native CI jobs must complete before
merging an upgrade.

## Updating the database seed

The source artifact is a PostgreSQL 18 plain logical dump compressed with
deterministic gzip. It deliberately contains schema and data only; role and
privilege policy lives in separate initialization scripts.

1. Restore the proposed source into a clean container using the exact
   PostgreSQL base image.
2. Run the structural/count checks in `db_image/init/99_verify.sql`.
3. Produce a fresh dump from PostgreSQL 18:

   ```bash
   pg_dump \
     --username=stat315_admin \
     --dbname=sqlda \
     --format=plain \
     --no-owner \
     --no-privileges \
     --no-table-access-method \
     --no-tablespaces \
     --encoding=UTF8 \
     --file=datadump.sql
   gzip -9n datadump.sql
   ```

4. Replace `db_image/datadump.sql.gz`, update every expected count if needed,
   increment the dataset marker and release tag, and change the Compose volume
   name (for example, from `seed1` to `seed2`).
5. Run the full integration script on a clean volume and let both native CI
   jobs pass.

PostgreSQL's official entrypoint processes initialization files only when the
database volume is empty. This is why a new seed must also receive a new volume
name.

## Publishing

Merge a green pull request to `main`, open **Actions → Publish course images →
Run workflow**, and enter an immutable course tag. The workflow will stop before
publication if either architecture fails. After it succeeds, verify that each
package is public and that the release tag contains both Linux platforms. Then
update `compose.yaml` only if the release tag changed.
