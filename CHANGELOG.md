# Changelog

## Unreleased

- Restore the prescribed pgAdmin server registration on every launch so an
  existing but incomplete pgAdmin settings volume cannot leave the **Servers**
  tree empty. Add a persisted-profile regression test on both native AMD64 and
  ARM64 CI runners, and require the expected registration in the pgAdmin health
  check.
- Add a writable, Git-ignored `student_sql` host folder that appears as
  `/home/student_sql` in pgAdmin while keeping course examples under
  `/home/sql_scripts` read-only.
- Run pgAdmin as the configurable non-root host user ID and start it with the
  fresh `pgadmin_data_v2` settings volume, so native-Linux students can save
  host-owned scripts without changing broad folder permissions. Existing
  PostgreSQL data is not affected. Prior pgAdmin-local settings and history are
  not migrated; pgAdmin recreates the supplied course server registration.
- Extend integration coverage to verify that a SQL script written through the
  pgAdmin container remains after restart, ordinary shutdown, and volume reset.

## 2026-fall.1

- Move student image distribution from personal Docker Hub repositories to the
  `tamu-stat315` GitHub Container Registry namespace.
- Upgrade to PostgreSQL 18.6, Python 3.14.7, JupyterLab 4.6.3, Notebook 7.6.2,
  and pgAdmin 4 9.17.
- Recreate and compress the course dataset as a portable PostgreSQL 18 logical
  dump, with startup integrity checks for all course relations and extensions.
- Add a locked Python environment with native AMD64 and ARM64 requirements.
- Remove embedded database-superuser credentials from the sample notebook.
- Add a restricted student database role and writable `student_work` schema.
- Bind web interfaces to localhost, stop exposing PostgreSQL, add persistent
  volumes and health checks, and run service processes without root privileges.
- Add complete integration tests, native dual-architecture CI, dependency
  updates, and manual gated multi-platform GHCR publication with provenance and
  SBOM attestations.
