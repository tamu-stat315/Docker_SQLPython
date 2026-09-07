# Security policy

## Intended use

This is a local classroom development environment, not a production database
deployment. Its documented default passwords and Jupyter token are convenience
credentials for a single-user machine; they are not secrets.

The default configuration reduces the impact of common mistakes:

- JupyterLab and pgAdmin are published only on the loopback interface.
- PostgreSQL has no host port at all.
- The notebook and service processes run as non-root users.
- `no-new-privileges` is enabled for every service.
- PostgreSQL generates its administrator password locally and does not share it
  with the notebook or pgAdmin containers.
- Notebooks connect as `stat315_student`, not the database administrator.
- Course tables are read-only to students, and `public` is not writable.
- Student SQL work has a separate schema.
- Base images, Python dependencies, and CI actions are version- and
  digest-pinned; release images include provenance and SBOM attestations.

Do not expose these ports to a campus network, cloud host, public tunnel, or
shared server with the defaults. If the environment must be reachable by other
machines, first replace every value in `.env`, add TLS and an appropriate access
control layer, and review PostgreSQL and Jupyter security separately.

Code run in a notebook can read starter files in `jupyter_notebooks`, can change
files in `student_notebooks`, and can create or modify objects in the
`student_work` database schema. Only run notebooks from sources you trust.

## Reporting a vulnerability

Please use the repository's **Security → Report a vulnerability** feature to
send a private report to the STAT 315 organization maintainers. Include the
affected release tag, operating system/architecture, reproduction steps, and
any relevant sanitized logs. Do not include passwords, tokens, or student data
in a public issue.
