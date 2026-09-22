#!/usr/bin/env bash
# Sobe um Postgres descartável, aplica as migrations sobre um stub do auth do
# Supabase e roda os testes. Uso: supabase/tests/run.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$here/.."
bin="${PG_BIN:-$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)}"
data="$(mktemp -d)"
port="${PG_PORT:-54329}"
trap '"$bin/pg_ctl" -D "$data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$data"' EXIT

"$bin/initdb" -D "$data" -U postgres --auth=trust >/dev/null
"$bin/pg_ctl" -D "$data" -o "-p $port -k $data" -l "$data/log" start >/dev/null

psql=(psql -h "$data" -p "$port" -U postgres -d postgres -v ON_ERROR_STOP=1 -q)
"${psql[@]}" -f "$here/auth_stub.sql"
for f in "$root"/migrations/*.sql; do
  echo "→ $(basename "$f")"
  "${psql[@]}" -f "$f"
done
"${psql[@]}" -f "$here/schema_test.sql"
