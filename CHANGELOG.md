# Changelog

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
