# STAT 315 SQL + Python environment

This repository starts the complete local environment used in STAT 315:

- PostgreSQL 18.6 with the course database already loaded
- Python 3.14.7 with a reproducibly locked data-science environment
- JupyterLab 4.6
- pgAdmin 4 9.17 with the course server already registered

The published images support both Intel/AMD (`linux/amd64`) and Apple
Silicon/ARM (`linux/arm64`). Docker selects the correct version automatically.
Students pull all three course images from the STAT 315 organization on GitHub
Container Registry (GHCR); a Docker Hub account is not required.

## Student quick start

Install and start [Docker Desktop](https://www.docker.com/products/docker-desktop/),
then download this repository and open a terminal in its folder.

```bash
docker compose pull
docker compose up --detach --wait
```

The first clean start, including the first start after a reset, can take several
minutes. Docker downloads the images, then PostgreSQL restores and validates
the course dataset. The command intentionally waits until all three services
are healthy, so leave the terminal open. Later starts reuse the initialized
database volume and are much faster.

Open the tools in a browser:

- JupyterLab: <http://localhost:8888/lab?token=stat315>
- pgAdmin: <http://localhost:5050>

pgAdmin opens directly in local desktop mode and already contains a server
named **STAT 315 PostgreSQL 18**. No pgAdmin login or database-password entry is
required with the default configuration.

The sample notebook demonstrates the recommended database connection:

```python
from sqlalchemy import text
from stat315_db import engine

with engine.connect() as connection:
    rows = connection.execute(
        text("SELECT * FROM customers LIMIT 5")
    ).fetchall()
```

No password needs to be copied into a notebook. The helper safely constructs
the connection from settings supplied by the container.

## Saving work and stopping

Starter notebooks appear under `course_examples` in JupyterLab and are
read-only. Use **File → Save Notebook As** to save a working copy under
`student_notebooks`. Those files are ignored by Git and remain on the computer
even when containers are stopped, replaced, or the course repository is
updated. Students should create their own SQL objects explicitly in the
writable `student_work` schema; they persist in a Docker volume.

In pgAdmin, course SQL examples are read-only under `/home/sql_scripts`. Save an
important query to the host (or paste it into a file under `student_notebooks`)
before performing a database reset, which intentionally removes pgAdmin state.

Stop the environment without deleting work:

```bash
docker compose down
```

Start it again with `docker compose up --detach --wait`.

## Updating

After downloading a newer copy of this repository:

```bash
docker compose pull
docker compose up --detach --wait
```

Published course tags are immutable. A dataset change receives a new tag and a
new versioned database volume, preventing PostgreSQL major-version upgrades
from accidentally reusing an incompatible data directory.

## Resetting the database

This removes the local database and pgAdmin state, then recreates both from the
course images. Files in `student_notebooks` are not removed.

```bash
docker compose down --volumes
docker compose up --detach --wait
```

The first command is intentionally destructive to SQL work saved only inside
the database volume. Export anything important before using it.

## Troubleshooting

Check service health and recent logs:

```bash
docker compose ps
docker compose logs --tail=100
```

If port 8888 or 5050 is already in use, copy [`.env.example`](.env.example) to
`.env` and change `JUPYTER_PORT` or `PGADMIN_PORT`. If Docker Desktop was just
installed, make sure it is running before issuing Compose commands. An
`unauthorized`, `manifest unknown`, or `no matching manifest` pull error is a
course-release problem; students should not force an Intel image or substitute
an old Docker Hub image.

Apple Silicon students should leave Docker's platform setting at its default;
the native ARM64 images are faster and more reliable than emulating Intel
images. Intel Windows, Linux, and Mac systems receive the AMD64 images.

## What is different from the legacy environment?

- The database is restored from a portable PostgreSQL 18 logical dump on the
  first clean start instead of copying a preinitialized database filesystem.
- Python packages come from a committed `uv.lock`, rather than many unrelated
  `pip install` layers.
- Jupyter runs as an unprivileged user and PostgreSQL is not published to the
  host network.
- PostgreSQL generates an installation-local administrator password that is
  never shared with the notebook or pgAdmin services.
- Course data is read-only to `stat315_student`; student-created objects go in
  `student_work`. The notebook no longer uses the database superuser.
- The web tools bind only to `127.0.0.1`, health checks control startup order,
  and the database and pgAdmin volumes are persistent.
- Every release is exercised on native AMD64 and ARM64 GitHub runners before
  the multi-platform GHCR images can be published.

Maintainer build, test, and release details are in
[`docs/MAINTAINERS.md`](docs/MAINTAINERS.md). The security model and safe-use
boundaries are documented in [`SECURITY.md`](SECURITY.md).
