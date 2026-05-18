#!/usr/bin/env bash
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<SQL
CREATE ROLE ${POSTGRES_REPLICATION_USER} WITH REPLICATION LOGIN PASSWORD '${POSTGRES_REPLICATION_PASSWORD}';
SQL

cat >> "$PGDATA/postgresql.conf" <<'EOF'
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on
EOF

cat >> "$PGDATA/pg_hba.conf" <<EOF
host replication ${POSTGRES_REPLICATION_USER} 0.0.0.0/0 md5
host all all 0.0.0.0/0 md5
EOF
