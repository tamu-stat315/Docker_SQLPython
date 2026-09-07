# syntax=docker/dockerfile:1.7
FROM postgres:18.6-trixie@sha256:4ef4dbc939d61acea57712655ddb4b4ab27419c913f94cca0cd57cb3ea3c2280

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
