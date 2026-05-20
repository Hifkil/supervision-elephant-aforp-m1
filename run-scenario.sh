#!/usr/bin/env bash
set -euo pipefail

SCENARIO="${1:-help}"
ASSUME_YES=0

if [ "${2:-}" = "--yes" ] || [ "${2:-}" = "-y" ]; then
  ASSUME_YES=1
fi

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
DIM='\033[2m'
RESET='\033[0m'

section() {
  echo ""
  echo -e "${BOLD}$1${RESET}"
  echo -e "${DIM}──────────────────────────────────────────${RESET}"
}

info() {
  echo -e "${CYAN}→${RESET} $1"
}

ok() {
  echo -e "${GREEN}✓${RESET} $1"
}

warn() {
  echo -e "${YELLOW}!${RESET} $1"
}

fail() {
  echo -e "${RED}✗${RESET} $1" >&2
}

confirm() {
  local message="$1"

  if [ "$ASSUME_YES" -eq 1 ]; then
    return 0
  fi

  echo ""
  read -r -p "$message [y/N] " answer
  case "$answer" in
    y|Y|yes|YES|oui|OUI) ;;
    *)
      fail "Action annulée."
      exit 1
      ;;
  esac
}

compose() {
  docker compose "$@"
}

wait_seconds() {
  local seconds="$1"
  info "Attente ${seconds}s pour laisser les checks se mettre à jour..."
  sleep "$seconds"
}

show_urls() {
  section "Interfaces à observer"
  echo -e "HAProxy web      ${CYAN}http://localhost${RESET}"
  echo -e "HAProxy stats    ${CYAN}http://localhost:8404/stats${RESET}"
  echo -e "Nagios           ${CYAN}http://localhost:8081/nagios${RESET}"
  echo -e "Zabbix           ${CYAN}http://localhost:8080${RESET}"
  echo -e "Prometheus       ${CYAN}http://localhost:9090/targets${RESET}"
  echo -e "Grafana          ${CYAN}http://localhost:3000${RESET}"
  echo -e "Graylog          ${CYAN}http://localhost:9000${RESET}"
}

show_status() {
  section "État Compose"
  compose ps artweb01p artweb02p arthpx01p artbdd01p artbdd02p artgra01p artrsy01p artspl01p artpgr01p artnag01p || true
}

show_nagios_subset() {
  local pattern="$1"

  section "Extrait Nagios"
  compose exec -T artnag01p sh -lc '
python3 - "$1" <<'"'"'PY'"'"'
import re
import sys
from pathlib import Path

pattern = re.compile(sys.argv[1])
text = Path("/opt/nagios/var/status.dat").read_text(errors="ignore")

for block in text.split("servicestatus {")[1:]:
    fields = {}
    for line in block.splitlines():
        line = line.strip()
        if "=" in line:
            key, value = line.split("=", 1)
            fields[key] = value

    host = fields.get("host_name", "")
    service = fields.get("service_description", "")
    output = fields.get("plugin_output", "")
    if not pattern.search(host + " " + service):
        continue

    state = fields.get("current_state", "?")
    state_name = {"0": "OK", "1": "WARNING", "2": "CRITICAL", "3": "UNKNOWN"}.get(state, state)
    print(f"{host:14} | {service:32} | {state_name:8} | {output}")
PY
' sh "$pattern" || true
}

recreate_sidecar() {
  local service="$1"
  info "Recréation du sidecar ${service}"
  compose up -d --force-recreate --no-deps "$service" >/dev/null
}

send_log() {
  local message="$1"

  if command -v logger >/dev/null 2>&1; then
    logger -n 127.0.0.1 -P 10514 -T "$message" || true
    ok "Log de test envoyé vers Rsyslog : $message"
  else
    warn "Commande logger indisponible sur l'hôte, log de test ignoré."
  fi
}

web_down() {
  section "Scénario 1 - Perte de artweb01p"
  show_urls
  show_status
  confirm "Arrêter artweb01p maintenant ?"

  compose stop nginx-exporter-artweb01p zabbix-agent-artweb01p artweb01p
  ok "artweb01p et ses sidecars arrêtés."

  section "Preuve de continuité HAProxy"
  curl -fsS http://localhost || true

  warn "À montrer : HAProxy stats voit artweb01p DOWN et artweb02p UP."
  wait_seconds 75
  show_nagios_subset 'artweb01p|arthpx01p'
}

web_restore() {
  section "Retour à la normale - artweb01p"
  compose start artweb01p
  recreate_sidecar nginx-exporter-artweb01p
  recreate_sidecar zabbix-agent-artweb01p
  wait_seconds 20

  compose ps artweb01p nginx-exporter-artweb01p zabbix-agent-artweb01p
  curl -fsS http://localhost >/dev/null
  ok "artweb01p restauré et HAProxy répond."
}

db_down() {
  section "Scénario 2 - Perte de la réplique artbdd02p"
  show_urls
  show_status

  section "Rôles PostgreSQL avant panne"
  compose exec -T artbdd01p psql -U artemis -d artemis -c "select pg_is_in_recovery();"
  compose exec -T artbdd02p psql -U artemis -d artemis -c "select pg_is_in_recovery();"

  confirm "Arrêter artbdd02p maintenant ?"
  compose stop postgres-exporter-artbdd02p zabbix-agent-artbdd02p artbdd02p
  ok "artbdd02p et ses sidecars arrêtés."

  section "Preuve que le primaire reste disponible"
  compose exec -T artbdd01p pg_isready -U artemis -d artemis -h 127.0.0.1

  wait_seconds 75
  show_nagios_subset 'artbdd01p|artbdd02p'
}

db_restore() {
  section "Retour à la normale - artbdd02p"
  compose start artbdd02p
  compose up -d --force-recreate --no-deps postgres-exporter-artbdd02p >/dev/null
  recreate_sidecar zabbix-agent-artbdd02p
  wait_seconds 35

  compose ps artbdd02p postgres-exporter-artbdd02p zabbix-agent-artbdd02p
  compose exec -T artbdd02p psql -U artemis -d artemis -c "select pg_is_in_recovery();"
  ok "Réplique PostgreSQL restaurée."
}

siem_down() {
  section "Scénario 3 - Perte du collecteur Rsyslog"
  show_urls
  show_status

  section "État SIEM avant panne"
  curl -fsS http://localhost:9000/api/system/lbstatus
  echo ""
  send_log "artemis demo log avant panne"

  confirm "Arrêter artrsy01p maintenant ?"
  compose stop zabbix-agent-artrsy01p artrsy01p
  ok "artrsy01p et son sidecar arrêtés."

  warn "À montrer : Graylog et Splunk restent accessibles, mais le relais Rsyslog est down."
  wait_seconds 75
  show_nagios_subset 'artrsy01p|artgra01p|artspl01p'
}

siem_restore() {
  section "Retour à la normale - artrsy01p"
  compose start artrsy01p
  recreate_sidecar zabbix-agent-artrsy01p
  wait_seconds 20

  compose ps artrsy01p zabbix-agent-artrsy01p
  compose exec -T artzab01p zabbix_get -s artrsy01p -k agent.ping
  send_log "artemis demo log apres retour rsyslog"
  ok "Collecteur Rsyslog restauré."
}

restore_all() {
  section "Retour global à la normale"
  compose start artweb01p artbdd02p artrsy01p
  compose up -d --force-recreate --no-deps \
    nginx-exporter-artweb01p \
    postgres-exporter-artbdd02p \
    zabbix-agent-artweb01p \
    zabbix-agent-artbdd02p \
    zabbix-agent-artrsy01p >/dev/null

  wait_seconds 35
  show_status
  ok "Restauration globale terminée."
}

help() {
  cat <<'EOF'
Usage:
  ./run-scenario.sh <scenario> [--yes]

Scénarios:
  web-down          Arrête artweb01p et montre la continuité HAProxy
  web-restore       Redémarre artweb01p, son exporter et son agent Zabbix

  db-down           Arrête la réplique PostgreSQL artbdd02p
  db-restore        Redémarre artbdd02p, son exporter et son agent Zabbix

  siem-down         Arrête le collecteur Rsyslog artrsy01p
  siem-restore      Redémarre artrsy01p et son agent Zabbix

  restore-all       Redémarre les services utilisés par les scénarios
  status            Affiche les services principaux
  urls              Affiche les URLs à ouvrir pendant la démo

Option:
  --yes, -y         Ne demande pas de confirmation avant l'injection de panne

Exemples:
  ./run-scenario.sh web-down
  ./run-scenario.sh web-restore
  ./run-scenario.sh db-down --yes
EOF
}

case "$SCENARIO" in
  web-down) web_down ;;
  web-restore) web_restore ;;
  db-down) db_down ;;
  db-restore) db_restore ;;
  siem-down) siem_down ;;
  siem-restore) siem_restore ;;
  restore-all) restore_all ;;
  status) show_status ;;
  urls) show_urls ;;
  help|-h|--help) help ;;
  *)
    fail "Scénario inconnu : $SCENARIO"
    help
    exit 1
    ;;
esac
