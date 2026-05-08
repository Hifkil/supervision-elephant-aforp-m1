#!/usr/bin/env bash
# Crée les hosts Artemis dans Zabbix via l'API JSON-RPC.
# Usage : ./zabbix/setup-hosts.sh
set -euo pipefail

API="http://localhost:8080/api_jsonrpc.php"
USER="Admin"
PASS="zabbix"

GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
api() {
  curl -sf -X POST "$API" \
    -H "Content-Type: application/json" \
    -d "$1"
}

json_get() {
  # Extraire une valeur scalaire d'un JSON simple avec python3
  python3 -c "import sys,json; d=json.load(sys.stdin); print($2)" 2>/dev/null
}

# ── Authentification ──────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  Zabbix — Setup des hosts Artemis${RESET}"
echo -e "${DIM}  ──────────────────────────────────────────${RESET}"
echo ""

printf "  Authentification...          "
TOKEN=$(api '{
  "jsonrpc":"2.0","method":"user.login","id":1,
  "params":{"username":"'"$USER"'","password":"'"$PASS"'"}
}' | json_get - "d['result']")

if [ -z "$TOKEN" ]; then
  echo -e "${RED}✗ Échec — vérifiez que artzabweb01p est démarré${RESET}"
  exit 1
fi
echo -e "${GREEN}✓${RESET}"

# ── Récupération des IDs ──────────────────────────────────────────────────────
get_template() {
  api '{
    "jsonrpc":"2.0","method":"template.get","id":2,"auth":"'"$TOKEN"'",
    "params":{"filter":{"host":["'"$1"'"]}}
  }' | json_get - "d['result'][0]['templateid']"
}

get_group() {
  api '{
    "jsonrpc":"2.0","method":"hostgroup.get","id":3,"auth":"'"$TOKEN"'",
    "params":{"filter":{"name":["'"$1"'"]}}
  }' | json_get - "d['result'][0]['groupid']"
}

printf "  Templates & groupes...       "
TPL_LINUX=$(get_template  "Linux by Zabbix agent")
TPL_NGINX=$(get_template  "Nginx by Zabbix agent")
TPL_HAPRX=$(get_template  "HAProxy by HTTP")
GRP=$(get_group "Linux servers")

if [ -z "$TPL_LINUX" ] || [ -z "$TPL_NGINX" ] || [ -z "$TPL_HAPRX" ]; then
  echo -e "${RED}✗ Templates introuvables${RESET}"
  exit 1
fi
echo -e "${GREEN}✓${RESET}"

# ── Création d'un host ────────────────────────────────────────────────────────
create_host() {
  local name=$1 templates=$2 macros=$3
  local result
  result=$(api '{
    "jsonrpc":"2.0","method":"host.create","id":4,"auth":"'"$TOKEN"'",
    "params":{
      "host":"'"$name"'",
      "interfaces":[{"type":1,"main":1,"useip":0,"ip":"","dns":"'"$name"'","port":"10050"}],
      "groups":[{"groupid":"'"$GRP"'"}],
      "templates":'"$templates"',
      "macros":'"$macros"'
    }
  }')

  # Vérifier s'il y a une erreur (host déjà existant, etc.)
  local err
  err=$(echo "$result" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('error',{}).get('data',''))" 2>/dev/null)

  if [ -n "$err" ]; then
    echo -e "${RED}✗  $err${RESET}"
  else
    echo -e "${GREEN}✓  UP${RESET}"
  fi
}

# ── Hosts nginx ───────────────────────────────────────────────────────────────
NGINX_TPL='[{"templateid":"'"$TPL_LINUX"'"},{"templateid":"'"$TPL_NGINX"'"}]'
NGINX_MAC='[
  {"macro":"{$NGINX.STUB_STATUS.HOST}","value":"127.0.0.1"},
  {"macro":"{$NGINX.STUB_STATUS.PORT}","value":"80"},
  {"macro":"{$NGINX.STUB_STATUS.PATH}","value":"/nginx_status"}
]'

echo -e "${BOLD}  Création des hosts${RESET}"
echo -e "${DIM}  ──────────────────────────────────────────${RESET}"
printf "  %-28s" "artweb01p"
create_host "artweb01p" "$NGINX_TPL" "$NGINX_MAC"

printf "  %-28s" "artweb02p"
create_host "artweb02p" "$NGINX_TPL" "$NGINX_MAC"

# ── Host HAProxy ──────────────────────────────────────────────────────────────
HAPRX_TPL='[{"templateid":"'"$TPL_LINUX"'"},{"templateid":"'"$TPL_HAPRX"'"}]'
HAPRX_MAC='[
  {"macro":"{$HAPROXY.STATS.HOST}","value":"arthpx01p"},
  {"macro":"{$HAPROXY.STATS.URI}","value":"/"},
  {"macro":"{$HAPROXY.STATS.PORT}","value":"8406"}
]'

printf "  %-28s" "arthpx01p"
create_host "arthpx01p" "$HAPRX_TPL" "$HAPRX_MAC"

echo ""
echo -e "  ${DIM}Monitoring → Hosts pour voir les statuts.${RESET}"
echo -e "  ${DIM}Optionnel : ./zabbix/setup-dashboard.py pour créer le dashboard Artemis.${RESET}"
echo ""
