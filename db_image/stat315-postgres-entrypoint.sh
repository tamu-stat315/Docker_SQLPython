#!/usr/bin/env bash
set -Eeuo pipefail

# The course services never need the database administrator's password. Create
# a one-time random bootstrap value instead of publishing a reusable password
# in the Compose file. Final initialization removes password login from the
# administrator role; local socket maintenance remains available.
if [[ -z "${POSTGRES_PASSWORD:-}" ]]; then
  POSTGRES_PASSWORD="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
  export POSTGRES_PASSWORD
fi

exec docker-entrypoint.sh "$@"
