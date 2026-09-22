#!/usr/bin/env bash
set -Eeuo pipefail

readonly PROJECT_NAME="stat315-e2e-${STAT315_E2E_RUN_ID:-${GITHUB_RUN_ID:-$$}}"

normalize_machine() {
  case "$1" in
    arm64 | aarch64 | linux/arm64 | linux/arm64/*) printf 'aarch64\n' ;;
    amd64 | x86_64 | linux/amd64 | linux/amd64/*) printf 'x86_64\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

default_machine=$(normalize_machine "$(uname -m)")
expected_machine=$(normalize_machine \
  "${EXPECTED_MACHINE:-${DOCKER_DEFAULT_PLATFORM:-$default_machine}}")
readonly EXPECTED_MACHINE="$expected_machine"
readonly NOTEBOOK_SENTINEL="student_notebooks/.stat315-e2e-persistence"
readonly SQL_SENTINEL="student_sql/.stat315-e2e-persistence.sql"
original_notebook_mode=""
startup_wait_timeout=600
restart_wait_timeout=300
kernel_startup_timeout=60
notebook_cell_timeout=180

export JUPYTER_PORT="${JUPYTER_PORT:-18888}"
export PGADMIN_PORT="${PGADMIN_PORT:-15050}"
export STAT315_STUDENT_PASSWORD="${STAT315_STUDENT_PASSWORD:-e2e:student\\password}"
export STAT315_JUPYTER_TOKEN="${STAT315_JUPYTER_TOKEN:-e2e-token}"
export STAT315_HOST_UID="${STAT315_HOST_UID:-$(id -u)}"

compose=(
  docker compose
  --project-name "$PROJECT_NAME"
  --file compose.yaml
  --file compose.dev.yaml
)

# Cross-architecture execution through QEMU is dramatically slower than either
# native student platform. Keep production health budgets strict while allowing
# this same suite to validate an emulated image to completion.
if [[ "$EXPECTED_MACHINE" != "$default_machine" ]]; then
  compose+=(--file tests/compose.emulation.yaml)
  startup_wait_timeout=1800
  restart_wait_timeout=1200
  kernel_startup_timeout=600
  notebook_cell_timeout=900
fi
readonly STARTUP_WAIT_TIMEOUT="$startup_wait_timeout"
readonly RESTART_WAIT_TIMEOUT="$restart_wait_timeout"
readonly KERNEL_STARTUP_TIMEOUT="$kernel_startup_timeout"
readonly NOTEBOOK_CELL_TIMEOUT="$notebook_cell_timeout"

cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM

  if ((exit_code != 0)); then
    "${compose[@]}" ps || true
    "${compose[@]}" logs --no-color || true
  fi

  "${compose[@]}" down --volumes --remove-orphans || true
  rm -f "$NOTEBOOK_SENTINEL"
  rm -f "$SQL_SENTINEL"
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

assert_pgadmin_registration() {
  "${compose[@]}" exec -T pgadmin /venv/bin/python3 - <<'PY'
import json
import sqlite3

import psycopg

database = sqlite3.connect("/var/lib/pgadmin/pgadmin4.db")
servers = database.execute(
    "SELECT name, host, port, maintenance_db, username, connection_params "
    "FROM server ORDER BY id"
).fetchall()
expected = (
    "STAT 315 PostgreSQL 18",
    "postgres",
    5432,
    "sqlda",
    "stat315_student",
)
if len(servers) != 1 or servers[0][:5] != expected:
    raise SystemExit(f"Unexpected pgAdmin server registrations: {servers!r}")
connection_params = json.loads(servers[0][5])
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
"${compose[@]}" up --detach --wait --wait-timeout "$STARTUP_WAIT_TIMEOUT"

printf 'Checking native container architectures...\n'
for service in postgres notebook pgadmin; do
  actual_machine=$("${compose[@]}" exec -T "$service" uname -m | tr -d '\r')
  assert_equal "$actual_machine" "$EXPECTED_MACHINE" "$service architecture"
done

pgadmin_process_uid=$("${compose[@]}" exec -T pgadmin \
  sh -c "awk '/^Uid:/{print \$2}' /proc/1/status" | tr -d '\r')
assert_equal "$pgadmin_process_uid" "$STAT315_HOST_UID" "pgAdmin process uid"

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
  --ExecutePreprocessor.startup_timeout="$KERNEL_STARTUP_TIMEOUT" \
  --ExecutePreprocessor.timeout="$NOTEBOOK_CELL_TIMEOUT"

printf 'Checking the student-facing web services...\n'
curl --fail --silent --show-error \
  --retry 20 --retry-all-errors --retry-delay 2 \
  "http://127.0.0.1:${JUPYTER_PORT}/lab?token=${STAT315_JUPYTER_TOKEN}" \
  >/dev/null
curl --fail --silent --show-error \
  --retry 20 --retry-all-errors --retry-delay 2 \
  "http://127.0.0.1:${PGADMIN_PORT}/misc/ping" \
  >/dev/null

assert_pgadmin_registration

printf 'Checking repair of an initialized pgAdmin profile with no servers...\n'
"${compose[@]}" stop pgadmin
"${compose[@]}" run --rm --no-deps \
  --entrypoint /venv/bin/python3 \
  pgadmin \
  -c 'import sqlite3; database = sqlite3.connect("/var/lib/pgadmin/pgadmin4.db"); database.execute("DELETE FROM server"); database.commit()'
"${compose[@]}" up --detach --wait --wait-timeout "$RESTART_WAIT_TIMEOUT"
assert_pgadmin_registration

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

"${compose[@]}" exec -T pgadmin \
  sh -c 'printf "%s\n" "SELECT 315 AS persistence_check;" > /home/student_sql/.stat315-e2e-persistence.sql'
grep -qx 'SELECT 315 AS persistence_check;' "$SQL_SENTINEL"
git check-ignore --quiet "$SQL_SENTINEL"

"${compose[@]}" restart
"${compose[@]}" up --detach --wait --wait-timeout "$RESTART_WAIT_TIMEOUT"
student_psql --tuples-only --no-align \
  --command='SELECT value FROM student_work._persistence_check' \
  | grep -qx '315'
grep -qx 'persistent' "$NOTEBOOK_SENTINEL"
grep -qx 'SELECT 315 AS persistence_check;' "$SQL_SENTINEL"

"${compose[@]}" down
"${compose[@]}" up --detach --wait --wait-timeout "$RESTART_WAIT_TIMEOUT"
student_psql --tuples-only --no-align \
  --command='SELECT value FROM student_work._persistence_check' \
  | grep -qx '315'
grep -qx 'persistent' "$NOTEBOOK_SENTINEL"
grep -qx 'SELECT 315 AS persistence_check;' "$SQL_SENTINEL"

printf 'Checking an explicit database reset while preserving notebooks...\n'
"${compose[@]}" down --volumes
"${compose[@]}" up --detach --wait --wait-timeout "$STARTUP_WAIT_TIMEOUT"

reset_relation=$(student_psql --tuples-only --no-align \
  --command="SELECT to_regclass('student_work._persistence_check') IS NULL" \
  | tr -d '[:space:]')
assert_equal "$reset_relation" "t" "database reset"

student_psql --tuples-only --no-align \
  --command='SELECT count(*) FROM public.customers' \
  | grep -qx '50000'
grep -qx 'persistent' "$NOTEBOOK_SENTINEL"
grep -qx 'SELECT 315 AS persistence_check;' "$SQL_SENTINEL"

printf 'All STAT 315 integration checks passed on %s.\n' "$EXPECTED_MACHINE"
