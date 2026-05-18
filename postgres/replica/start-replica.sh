#!/usr/bin/env bash
set -euo pipefail

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  rm -rf "$PGDATA"/*

  until pg_isready -h "$POSTGRES_PRIMARY_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB"; do
    sleep 2
  done

  PGPASSWORD="$POSTGRES_REPLICATION_PASSWORD" pg_basebackup \
    -h "$POSTGRES_PRIMARY_HOST" \
    -D "$PGDATA" \
    -U "$POSTGRES_REPLICATION_USER" \
    -v \
    -P \
    -R

  chown -R postgres:postgres "$PGDATA"
fi

exec docker-entrypoint.sh postgres
