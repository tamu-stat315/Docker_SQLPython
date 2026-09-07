#!/usr/bin/env bash
set -Eeuo pipefail

readonly PROJECT_NAME="stat315-e2e-${STAT315_E2E_RUN_ID:-${GITHUB_RUN_ID:-$$}}"
default_machine=$(uname -m)
case "$default_machine" in
  arm64) default_machine=aarch64 ;;
  amd64) default_machine=x86_64 ;;
esac
readonly EXPECTED_MACHINE="${EXPECTED_MACHINE:-$default_machine}"
readonly NOTEBOOK_SENTINEL="student_notebooks/.stat315-e2e-persistence"
original_notebook_mode=""

export JUPYTER_PORT="${JUPYTER_PORT:-18888}"
export PGADMIN_PORT="${PGADMIN_PORT:-15050}"
export STAT315_STUDENT_PASSWORD="${STAT315_STUDENT_PASSWORD:-e2e:student\\password}"
export STAT315_JUPYTER_TOKEN="${STAT315_JUPYTER_TOKEN:-e2e-token}"

compose=(
  docker compose
  --project-name "$PROJECT_NAME"
  --file compose.yaml
  --file compose.dev.yaml
)

cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM

  if ((exit_code != 0)); then
    "${compose[@]}" ps || true
    "${compose[@]}" logs --no-color || true
  fi

  "${compose[@]}" down --volumes --remove-orphans || true
  rm -f "$NOTEBOOK_SENTINEL"
  if [[ -n "$original_notebook_mode" ]]; then
    chmod "$original_notebook_mode" student_notebooks
  fi
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

assert_equal() {
  local actual=$1
  local expected=$2
  local description=$3

  if [[ "$actual" != "$expected" ]]; then
    printf '%s: expected %q, found %q\n' "$description" "$expected" "$actual" >&2
    return 1
  fi
}

student_psql() {
  "${compose[@]}" exec -T \
    -e "PGPASSWORD=$STAT315_STUDENT_PASSWORD" \
    postgres \
    psql --host=postgres --username=stat315_student --dbname=sqlda \
    --set=ON_ERROR_STOP=1 "$@"
}

printf 'Validating Compose configuration...\n'
"${compose[@]}" config --quiet

# A GitHub-hosted runner owns this checkout as uid 1001, while the deliberately
# non-root notebook image uses uid 1000. Save and restore the directory mode so
# the CI-only compatibility adjustment never leaves a world-writable checkout.
if original_notebook_mode=$(stat -c '%a' student_notebooks 2>/dev/null); then
  :
else
  original_notebook_mode=$(stat -f '%Lp' student_notebooks)
fi
chmod a+rwx student_notebooks

"${compose[@]}" down --volumes --remove-orphans

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  printf 'Building all course images...\n'
  "${compose[@]}" build --pull
fi

printf 'Starting the complete student stack...\n'
"${compose[@]}" up --detach --wait --wait-timeout 600

printf 'Checking native container architectures...\n'
for service in postgres notebook pgadmin; do
  actual_machine=$("${compose[@]}" exec -T "$service" uname -m | tr -d '\r')
  assert_equal "$actual_machine" "$EXPECTED_MACHINE" "$service architecture"
done

printf 'Checking network exposure and non-root processes...\n'
postgres_container=$("${compose[@]}" ps --quiet postgres)
postgres_bindings=$(docker inspect \
  --format='{{json (index .HostConfig.PortBindings "5432/tcp")}}' \
  "$postgres_container")
assert_equal "$postgres_bindings" "null" "PostgreSQL host-port bindings"

for service in postgres notebook pgadmin; do
  process_uid=$("${compose[@]}" exec -T "$service" \
    sh -c "awk '/^Uid:/{print \$2}' /proc/1/status" | tr -d '\r')
  if [[ "$process_uid" == "0" ]]; then
    printf '%s primary process unexpectedly runs as root\n' "$service" >&2
    exit 1
  fi
done

for service in postgres notebook pgadmin; do
  security_options=$(docker inspect \
    --format='{{json .HostConfig.SecurityOpt}}' \
    "$("${compose[@]}" ps --quiet "$service")")
  if [[ "$security_options" != *'no-new-privileges:true'* ]]; then
    printf '%s is missing no-new-privileges\n' "$service" >&2
    exit 1
  fi
done

python3 - \
  "$("${compose[@]}" ps --quiet notebook)" \
  "$("${compose[@]}" ps --quiet pgadmin)" <<'PY'
import json
import subprocess
import sys

expected = ((sys.argv[1], "8888/tcp"), (sys.argv[2], "8080/tcp"))
for container_id, container_port in expected:
    inspection = json.loads(
        subprocess.check_output(["docker", "inspect", container_id])
    )[0]
    bindings = inspection["HostConfig"]["PortBindings"][container_port]
    if len(bindings) != 1 or bindings[0]["HostIp"] != "127.0.0.1":
        raise SystemExit(
            f"{container_port} is not loopback-only: {bindings!r}"
        )
PY

printf 'Verifying Python, packages, database contents, and privileges...\n'
"${compose[@]}" exec -T notebook python /opt/stat315/verify_environment.py

student_psql --tuples-only --no-align --command='SELECT 1' | grep -qx '1'

student_search_path=$(student_psql --tuples-only --no-align \
  --command='SHOW search_path' | tr -d '[:space:]')
assert_equal "$student_search_path" "public,student_work" "student search path"

if student_psql --command='CREATE TABLE public._must_not_exist (value integer)' \
  >/dev/null 2>&1; then
  printf 'The student role unexpectedly created a table in public\n' >&2
  exit 1
fi

if student_psql --command='DROP SCHEMA student_work CASCADE' \
  >/dev/null 2>&1; then
  printf 'The student role unexpectedly dropped the managed work schema\n' >&2
  exit 1
fi

role_flags=$("${compose[@]}" exec -T postgres \
  psql --username=stat315_admin --dbname=sqlda --tuples-only --no-align \
  --command="SELECT rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls FROM pg_roles WHERE rolname = 'stat315_student'" \
  | tr -d '[:space:]')
assert_equal "$role_flags" "f" "student elevated-role flags"

admin_password_disabled=$("${compose[@]}" exec -T postgres \
  psql --username=stat315_admin --dbname=sqlda --tuples-only --no-align \
  --command="SELECT rolpassword IS NULL FROM pg_authid WHERE rolname = 'stat315_admin'" \
  | tr -d '[:space:]')
assert_equal "$admin_password_disabled" "t" "administrator TCP password"

if "${compose[@]}" exec -T \
  -e PGPASSWORD=stat315_admin_local_only \
  postgres \
  psql --host=postgres --username=stat315_admin --dbname=sqlda \
  --command='SELECT 1' >/dev/null 2>&1; then
  printf 'The legacy public administrator password unexpectedly still works\n' >&2
  exit 1
fi

printf 'Executing the sample notebook from beginning to end...\n'
"${compose[@]}" exec -T notebook \
  jupyter nbconvert \
  --to notebook \
  --execute /home/stat315/workspace/course_examples/jupyternotebook.ipynb \
  --output stat315-executed.ipynb \
  --output-dir /tmp \
  --ExecutePreprocessor.timeout=180

printf 'Checking the student-facing web services...\n'
curl --fail --silent --show-error \
  --retry 20 --retry-all-errors --retry-delay 2 \
  "http://127.0.0.1:${JUPYTER_PORT}/lab?token=${STAT315_JUPYTER_TOKEN}" \
  >/dev/null
curl --fail --silent --show-error \
  --retry 20 --retry-all-errors --retry-delay 2 \
  "http://127.0.0.1:${PGADMIN_PORT}/misc/ping" \
  >/dev/null

"${compose[@]}" exec -T pgadmin /venv/bin/python3 - <<'PY'
import json
import sqlite3

import psycopg

database = sqlite3.connect("/var/lib/pgadmin/pgadmin4.db")
server = database.execute(
    "SELECT name, host, port, maintenance_db, username, connection_params "
    "FROM server WHERE name = ?",
    ("STAT 315 PostgreSQL 18",),
).fetchone()
expected = (
    "STAT 315 PostgreSQL 18",
    "postgres",
    5432,
    "sqlda",
    "stat315_student",
)
if server is None or server[:5] != expected:
    raise SystemExit(f"Unexpected pgAdmin server registration: {server!r}")
connection_params = json.loads(server[5])
if connection_params.get("passfile") != "/tmp/pgpassfile":
    raise SystemExit(f"Unexpected pgAdmin passfile: {connection_params!r}")

with psycopg.connect(
    "host=postgres port=5432 dbname=sqlda "
    "user=stat315_student passfile=/tmp/pgpassfile"
) as connection:
    customer_count = connection.execute(
        "SELECT count(*) FROM public.customers"
    ).fetchone()[0]
if customer_count != 50_000:
    raise SystemExit(f"pgAdmin connection found {customer_count} customers")
PY

printf 'Checking persistence across restart and ordinary shutdown...\n'
student_psql --command='CREATE TABLE student_work._persistence_check (value integer NOT NULL)'
student_psql --command='INSERT INTO student_work._persistence_check VALUES (315)'
"${compose[@]}" exec -T notebook \
  sh -c 'printf "%s\n" persistent > /home/stat315/workspace/student_notebooks/.stat315-e2e-persistence'

if "${compose[@]}" exec -T notebook \
  sh -c 'touch /home/stat315/workspace/course_examples/_must_not_exist' \
  >/dev/null 2>&1; then
  printf 'The course examples bind mount unexpectedly permits writes\n' >&2
  exit 1
fi

if "${compose[@]}" exec -T pgadmin \
  sh -c 'touch /home/sql_scripts/_must_not_exist' \
  >/dev/null 2>&1; then
  printf 'The course SQL bind mount unexpectedly permits writes\n' >&2
  exit 1
fi

"${compose[@]}" restart
"${compose[@]}" up --detach --wait --wait-timeout 300
student_psql --tuples-only --no-align \
  --command='SELECT value FROM student_work._persistence_check' \
  | grep -qx '315'
grep -qx 'persistent' "$NOTEBOOK_SENTINEL"

"${compose[@]}" down
"${compose[@]}" up --detach --wait --wait-timeout 300
student_psql --tuples-only --no-align \
  --command='SELECT value FROM student_work._persistence_check' \
  | grep -qx '315'
grep -qx 'persistent' "$NOTEBOOK_SENTINEL"

printf 'Checking an explicit database reset while preserving notebooks...\n'
"${compose[@]}" down --volumes
"${compose[@]}" up --detach --wait --wait-timeout 600

reset_relation=$(student_psql --tuples-only --no-align \
  --command="SELECT to_regclass('student_work._persistence_check') IS NULL" \
  | tr -d '[:space:]')
assert_equal "$reset_relation" "t" "database reset"

student_psql --tuples-only --no-align \
  --command='SELECT count(*) FROM public.customers' \
  | grep -qx '50000'
grep -qx 'persistent' "$NOTEBOOK_SENTINEL"

printf 'All STAT 315 integration checks passed on %s.\n' "$EXPECTED_MACHINE"
