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

get_host_id() {
  api '{
    "jsonrpc":"2.0","method":"host.get","id":5,"auth":"'"$TOKEN"'",
    "params":{"filter":{"host":["'"$1"'"]},"output":["hostid"]}
  }' | json_get - "d['result'][0]['hostid']"
}

get_interface_id() {
  api '{
    "jsonrpc":"2.0","method":"hostinterface.get","id":6,"auth":"'"$TOKEN"'",
    "params":{"hostids":["'"$1"'"],"output":["interfaceid"]}
  }' | json_get - "d['result'][0]['interfaceid']"
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
    if [[ "$err" == *"already exists"* ]]; then
      echo -e "${GREEN}✓  déjà présent${RESET}"
    else
      echo -e "${RED}✗  $err${RESET}"
    fi
  else
    echo -e "${GREEN}✓  UP${RESET}"
  fi
}

ensure_simple_check() {
  local host=$1 name=$2 key=$3 value_type=$4
  local hostid interfaceid itemid result err

  hostid=$(get_host_id "$host")
  interfaceid=$(get_interface_id "$hostid")

  itemid=$(api '{
    "jsonrpc":"2.0","method":"item.get","id":7,"auth":"'"$TOKEN"'",
    "params":{
      "hostids":["'"$hostid"'"],
      "filter":{"key_":["'"$key"'"]},
      "output":["itemid"]
    }
  }' | json_get - "d['result'][0]['itemid'] if d['result'] else ''")

  if [ -n "$itemid" ]; then
    result=$(api '{
      "jsonrpc":"2.0","method":"item.update","id":8,"auth":"'"$TOKEN"'",
      "params":{
        "itemid":"'"$itemid"'",
        "name":"'"$name"'",
        "delay":"30s",
        "status":0
      }
    }')
  else
    result=$(api '{
      "jsonrpc":"2.0","method":"item.create","id":9,"auth":"'"$TOKEN"'",
      "params":{
        "hostid":"'"$hostid"'",
        "interfaceid":"'"$interfaceid"'",
        "name":"'"$name"'",
        "key_":"'"$key"'",
        "type":3,
        "value_type":'"$value_type"',
        "delay":"30s"
      }
    }')
  fi

  err=$(echo "$result" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('error',{}).get('data',''))" 2>/dev/null)

  if [ -n "$err" ]; then
    echo -e "${RED}✗  ${host} — ${name}: ${err}${RESET}"
  else
    echo -e "${GREEN}✓  ${host} — ${name}${RESET}"
  fi
}

# ── Host Zabbix server ───────────────────────────────────────────────────────
LINUX_TPL='[{"templateid":"'"$TPL_LINUX"'"}]'
EMPTY_MAC='[]'

# ── Hosts nginx ───────────────────────────────────────────────────────────────
NGINX_TPL='[{"templateid":"'"$TPL_LINUX"'"},{"templateid":"'"$TPL_NGINX"'"}]'
NGINX_MAC='[
  {"macro":"{$NGINX.STUB_STATUS.HOST}","value":"127.0.0.1"},
  {"macro":"{$NGINX.STUB_STATUS.PORT}","value":"80"},
  {"macro":"{$NGINX.STUB_STATUS.PATH}","value":"/nginx_status"}
]'

echo -e "${BOLD}  Création des hosts${RESET}"
echo -e "${DIM}  ──────────────────────────────────────────${RESET}"
printf "  %-28s" "artzab01p"
create_host "artzab01p" "$LINUX_TPL" "$EMPTY_MAC"

printf "  %-28s" "artdb01p"
create_host "artdb01p" "$LINUX_TPL" "$EMPTY_MAC"

printf "  %-28s" "artzabweb01p"
create_host "artzabweb01p" "$LINUX_TPL" "$EMPTY_MAC"

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

for host in \
  artbdd01p \
  artbdd02p \
  artsft02p \
  artnfs01p \
  artbkp01p \
  artbbx01p \
  artmet01p \
  artprom01p \
  artgrf01p \
  artnag01p
do
  printf "  %-28s" "$host"
  create_host "$host" "$LINUX_TPL" "$EMPTY_MAC"
done

echo ""
echo -e "${BOLD}  Checks applicatifs Zabbix${RESET}"
echo -e "${DIM}  ──────────────────────────────────────────${RESET}"
ensure_simple_check "artzab01p" "Zabbix server TCP status" "net.tcp.service[tcp,,10051]" 3
ensure_simple_check "artdb01p" "Zabbix database TCP status" "net.tcp.service[tcp,,5432]" 3
ensure_simple_check "artzabweb01p" "Zabbix web HTTP status" "net.tcp.service[http,,8080]" 3
ensure_simple_check "artzabweb01p" "Zabbix web HTTP response time" "net.tcp.service.perf[http,,8080]" 0
ensure_simple_check "artsft02p" "SFTP SSH status" "net.tcp.service[ssh,,22]" 3
ensure_simple_check "artnfs01p" "NFS TCP status" "net.tcp.service[tcp,,2049]" 3
ensure_simple_check "artbkp01p" "Backup metrics HTTP status" "net.tcp.service[http,,8080]" 3
ensure_simple_check "artbkp01p" "Backup metrics HTTP response time" "net.tcp.service.perf[http,,8080]" 0
ensure_simple_check "artbdd01p" "PostgreSQL primary TCP status" "net.tcp.service[tcp,,5432]" 3
ensure_simple_check "artbdd01p" "PostgreSQL primary TCP response time" "net.tcp.service.perf[tcp,,5432]" 0
ensure_simple_check "artbdd02p" "PostgreSQL replica TCP status" "net.tcp.service[tcp,,5432]" 3
ensure_simple_check "artbdd02p" "PostgreSQL replica TCP response time" "net.tcp.service.perf[tcp,,5432]" 0
ensure_simple_check "artbbx01p" "Blackbox exporter TCP status" "net.tcp.service[tcp,,9115]" 3
ensure_simple_check "artmet01p" "Docker metrics HTTP status" "net.tcp.service[http,,8080]" 3
ensure_simple_check "artmet01p" "Docker metrics HTTP response time" "net.tcp.service.perf[http,,8080]" 0
ensure_simple_check "artprom01p" "Prometheus HTTP status" "net.tcp.service[http,,9090]" 3
ensure_simple_check "artprom01p" "Prometheus HTTP response time" "net.tcp.service.perf[http,,9090]" 0
ensure_simple_check "artgrf01p" "Grafana HTTP status" "net.tcp.service[http,,3000]" 3
ensure_simple_check "artgrf01p" "Grafana HTTP response time" "net.tcp.service.perf[http,,3000]" 0
ensure_simple_check "artnag01p" "Nagios HTTP status" "net.tcp.service[http,,80]" 3
ensure_simple_check "artnag01p" "Nagios HTTP response time" "net.tcp.service.perf[http,,80]" 0

echo ""
echo -e "  ${DIM}Monitoring → Hosts pour voir les statuts.${RESET}"
echo -e "  ${DIM}Dashboard : ./zabbix/setup-dashboard.py crée ou met à jour Artemis.${RESET}"
echo ""
