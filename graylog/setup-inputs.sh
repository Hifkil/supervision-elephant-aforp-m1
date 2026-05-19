#!/usr/bin/env bash
# Crée les inputs Syslog Graylog utilisés par artrsy01p.
set -euo pipefail

URL="${GRAYLOG_URL:-http://localhost:9000}"
USER="${GRAYLOG_USER:-admin}"
PASS="${GRAYLOG_PASSWORD:-graylogadmin}"

GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

api_get() {
  curl --max-time 20 -sf -u "$USER:$PASS" -H "X-Requested-By: artemis" "$URL$1"
}

api_post() {
  curl --max-time 20 -sf -u "$USER:$PASS" \
    -H "Content-Type: application/json" \
    -H "X-Requested-By: artemis" \
    -X POST "$URL$1" \
    -d "$2"
}

wait_api() {
  local elapsed=0
  while [ "$elapsed" -lt 180 ]; do
    if curl --max-time 5 -sf "$URL/api/system/lbstatus" | grep -q ALIVE; then
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done
  return 1
}

input_exists() {
  local title="$1"
  api_get "/api/system/inputs" | grep -q "\"title\":\"$title\""
}

create_syslog_tcp() {
  local title="$1"
  local port="$2"

  if input_exists "$title"; then
    echo -e "  ${GREEN}✓  $title déjà présent${RESET}"
    return 0
  fi

  api_post "/api/system/inputs" '{
    "title": "'"$title"'",
    "type": "org.graylog2.inputs.syslog.tcp.SyslogTCPInput",
    "global": true,
    "configuration": {
      "bind_address": "0.0.0.0",
      "port": '"$port"',
      "recv_buffer_size": 1048576,
      "number_worker_threads": 2,
      "tls_enable": false,
      "tls_cert_file": "",
      "tls_key_file": "",
      "tls_key_password": "",
      "tls_client_auth": "disabled",
      "tcp_keepalive": false,
      "use_null_delimiter": false,
      "max_message_size": 2097152,
      "override_source": "",
      "charset_name": "UTF-8",
      "expand_structured_data": false,
      "allow_override_date": true,
      "force_rdns": false,
      "store_full_message": true
    },
    "node": null
  }' >/dev/null

  echo -e "  ${GREEN}✓  $title créé${RESET}"
}

create_syslog_udp() {
  local title="$1"
  local port="$2"

  if input_exists "$title"; then
    echo -e "  ${GREEN}✓  $title déjà présent${RESET}"
    return 0
  fi

  api_post "/api/system/inputs" '{
    "title": "'"$title"'",
    "type": "org.graylog2.inputs.syslog.udp.SyslogUDPInput",
    "global": true,
    "configuration": {
      "bind_address": "0.0.0.0",
      "port": '"$port"',
      "recv_buffer_size": 1048576,
      "number_worker_threads": 2,
      "override_source": "",
      "charset_name": "UTF-8",
      "expand_structured_data": false,
      "allow_override_date": true,
      "force_rdns": false,
      "store_full_message": true
    },
    "node": null
  }' >/dev/null

  echo -e "  ${GREEN}✓  $title créé${RESET}"
}

echo ""
echo -e "${BOLD}  Configuration Graylog${RESET}"
echo -e "${DIM}  ──────────────────────────────────────────${RESET}"

if ! wait_api; then
  echo -e "  ${RED}✗  API Graylog indisponible${RESET}"
  exit 1
fi

create_syslog_tcp "Artemis syslog TCP" 1514
create_syslog_udp "Artemis syslog UDP" 1514
