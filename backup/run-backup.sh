#!/bin/sh
set -eu

SOURCE_DIR="${SOURCE_DIR:-/source}"
SFTP_DIR="${SFTP_DIR:-/backup/sftp}"
NFS_DIR="${NFS_DIR:-/backup/nfs}"
STATUS_DIR="${STATUS_DIR:-/status}"
INTERVAL_SECONDS="${BACKUP_INTERVAL_SECONDS:-300}"
METRICS_FILE="${STATUS_DIR}/metrics"
LAST_SUCCESS_FILE="${STATUS_DIR}/last_success"

last_success_timestamp() {
  if [ -s "$LAST_SUCCESS_FILE" ]; then
    read -r last_success < "$LAST_SUCCESS_FILE"
    printf '%s\n' "${last_success:-0}"
  else
    printf '0\n'
  fi
}

write_metrics() {
  status="$1"
  started_at="$2"
  ended_at="$3"
  copied_files="$4"
  last_success="$5"
  tmp="${METRICS_FILE}.tmp"

  {
    echo "# HELP artemis_backup_last_success_timestamp_seconds Last successful backup timestamp."
    echo "# TYPE artemis_backup_last_success_timestamp_seconds gauge"
    echo "artemis_backup_last_success_timestamp_seconds ${last_success}"
    echo "# HELP artemis_backup_last_status Last backup status, 0 success and 1 failure."
    echo "# TYPE artemis_backup_last_status gauge"
    echo "artemis_backup_last_status ${status}"
    echo "# HELP artemis_backup_last_duration_seconds Last backup duration."
    echo "# TYPE artemis_backup_last_duration_seconds gauge"
    echo "artemis_backup_last_duration_seconds $((ended_at - started_at))"
    echo "# HELP artemis_backup_copied_files Number of copied source files."
    echo "# TYPE artemis_backup_copied_files gauge"
    echo "artemis_backup_copied_files ${copied_files}"
    echo "# HELP artemis_backup_loop_interval_seconds Configured backup interval."
    echo "# TYPE artemis_backup_loop_interval_seconds gauge"
    echo "artemis_backup_loop_interval_seconds ${INTERVAL_SECONDS}"
  } > "$tmp"

  mv "$tmp" "$METRICS_FILE"
}

run_backup_once() {
  started_at="$(date +%s)"
  status=1
  copied_files=0
  last_success="$(last_success_timestamp)"

  if cp -a "${SOURCE_DIR}/." "${SFTP_DIR}/" && cp -a "${SOURCE_DIR}/." "${NFS_DIR}/"; then
    status=0
    copied_files="$(find "$SOURCE_DIR" -type f | wc -l)"
    ended_at="$(date +%s)"
    last_success="$ended_at"
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    printf '%s\n' "$timestamp" > "${SFTP_DIR}/LAST_BACKUP_UTC.txt"
    printf '%s\n' "$timestamp" > "${NFS_DIR}/LAST_BACKUP_UTC.txt"
    printf '%s\n' "$last_success" > "$LAST_SUCCESS_FILE"
  else
    ended_at="$(date +%s)"
  fi

  write_metrics "$status" "$started_at" "$ended_at" "$copied_files" "$last_success"
}

backup_loop() {
  while true; do
    run_backup_once
    sleep "$INTERVAL_SECONDS"
  done
}

mkdir -p "$SFTP_DIR" "$NFS_DIR" "$STATUS_DIR"
write_metrics 1 "$(date +%s)" "$(date +%s)" 0 "$(last_success_timestamp)"

backup_loop &
backup_pid="$!"
trap 'kill "$backup_pid" 2>/dev/null || true' INT TERM EXIT

httpd -f -p 8080 -h "$STATUS_DIR"
