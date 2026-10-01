# syntax=docker/dockerfile:1.7
FROM postgres:18.6-trixie@sha256:5a5a84b19854a9ffaa54082c166ff4ec27473a361e496e5ea167f298f2da9722

LABEL org.opencontainers.image.source="https://github.com/tamu-stat315/Docker_SQLPython"
LABEL org.opencontainers.image.description="PostgreSQL 18 seed image for the STAT 315 SQL course database"
LABEL org.opencontainers.image.licenses="MIT"

COPY --chmod=0755 init/00_roles.sh /docker-entrypoint-initdb.d/00_roles.sh
COPY datadump.sql.gz /docker-entrypoint-initdb.d/10_datadump.sql.gz
COPY init/90_access.sql /docker-entrypoint-initdb.d/90_access.sql
COPY init/99_verify.sql /docker-entrypoint-initdb.d/99_verify.sql
COPY --chmod=0755 stat315-postgres-entrypoint.sh /usr/local/bin/stat315-postgres-entrypoint.sh

ENTRYPOINT ["stat315-postgres-entrypoint.sh"]
CMD ["postgres"]
