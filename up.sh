#!/usr/bin/env bash
set -euo pipefail

# ── Couleurs ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

TIMEOUT=360   # secondes max d'attente par service (Splunk/Graylog peuvent prendre 3-5 min)
POLL=3        # intervalle de sondage (s)

# ── Bannière ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  ╔══════════════════════════════════════╗${RESET}"
echo -e "${BOLD}  ║     Artemis — Supervision Lab        ║${RESET}"
echo -e "${BOLD}  ╚══════════════════════════════════════╝${RESET}"
echo ""

# ── Démarrage des conteneurs ──────────────────────────────────────────────────
docker compose up -d --remove-orphans "$@"
echo ""

# Ces sidecars partagent le namespace réseau du service cible.
# Si un service cible a été recréé ou redémarré, on les recrée pour éviter
# qu'ils restent attachés à un ancien namespace sans port exposé.
mapfile -t NETWORK_SIDECAR_SERVICES < <(docker compose config --services | grep -E '^(zabbix-agent-|nginx-exporter-|postgres-exporter-)' || true)
if [ "${#NETWORK_SIDECAR_SERVICES[@]}" -gt 0 ]; then
  docker compose up -d --no-deps --force-recreate "${NETWORK_SIDECAR_SERVICES[@]}"
  echo ""
fi

# ── Fonction de vérification ──────────────────────────────────────────────────
# Affiche le label puis des points + marqueur toutes les 30s.
# Termine par ✓ UP / ✗ ERREUR / ✗ TIMEOUT selon le cas.
check_service() {
  local label="$1"
  local service="$2"

  printf "  %-28s" "$label"

  local elapsed=0 id status
  while [ $elapsed -lt $TIMEOUT ]; do
    id=$(docker compose ps -q "$service" 2>/dev/null || true)

    if [ -n "$id" ]; then
      # Healthcheck défini → attend "healthy" ; sinon vérifie "running"
      status=$(docker inspect \
        --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
        "$id" 2>/dev/null || echo "unknown")

      case "$status" in
        healthy|running)
          echo -e " ${GREEN}✓  UP${RESET} ${DIM}(${elapsed}s)${RESET}"
          return 0
          ;;
        unhealthy)
          echo -e " ${RED}✗  ERREUR${RESET}"
          echo -e "      ${DIM}→ docker compose logs $service${RESET}"
          return 0
          ;;
      esac
    fi

    # Marqueur toutes les 30 s pour rassurer que ça tourne
    if [ $((elapsed % 30)) -eq 0 ] && [ $elapsed -gt 0 ]; then
      printf "${YELLOW}${elapsed}s${RESET}"
    else
      printf "${DIM}.${RESET}"
    fi

    sleep $POLL
    elapsed=$((elapsed + POLL))
  done

  echo -e " ${RED}✗  TIMEOUT (${TIMEOUT}s)${RESET}"
  echo -e "      ${DIM}→ docker compose logs $service${RESET}"
}

print_access_row() {
  local name="$1"
  local url="$2"
  local login="${3:-Aucun}"
  local note="${4:-}"

  printf "  %-18b %-36b %-24b" "$name" "${CYAN}${url}${RESET}" "$login"
  if [ -n "$note" ]; then
    printf "%b" "${DIM}${note}${RESET}"
  fi
  echo ""
}

configure_zabbix() {
  echo ""
  echo -e "${BOLD}  Configuration Zabbix${RESET}"
  echo -e "${DIM}  ──────────────────────────────────────────${RESET}"

  if ./zabbix/setup-hosts.sh && ./zabbix/setup-dashboard.py; then
    echo -e "  ${GREEN}✓  Hosts et dashboard Artemis prêts${RESET}"
  else
    echo -e "  ${RED}✗  Configuration Zabbix incomplète${RESET}"
    echo -e "      ${DIM}→ relancer ./zabbix/setup-hosts.sh puis ./zabbix/setup-dashboard.py${RESET}"
  fi
}

configure_graylog() {
  echo ""
  echo -e "${BOLD}  Configuration SIEM / logs${RESET}"
  echo -e "${DIM}  ──────────────────────────────────────────${RESET}"

  if ./graylog/setup-inputs.sh; then
    echo -e "  ${GREEN}✓  Inputs Syslog Graylog prêts${RESET}"
  else
    echo -e "  ${RED}✗  Configuration Graylog incomplète${RESET}"
    echo -e "      ${DIM}→ relancer ./graylog/setup-inputs.sh après démarrage de artgra01p${RESET}"
  fi
}

# ── Vérification dans l'ordre de démarrage ────────────────────────────────────
echo -e "${BOLD}  État des services${RESET}"
echo -e "${DIM}  ──────────────────────────────────────────${RESET}"

check_service "artdb01p"              artdb01p
check_service "artzab01p"             artzab01p
check_service "agent → artdb01p"      zabbix-agent-artdb01p
check_service "agent → artzab01p"     zabbix-agent-artzab01p
check_service "artzabweb01p"          artzabweb01p
check_service "agent → artzabweb01p"  zabbix-agent-artzabweb01p
check_service "artweb01p"             artweb01p
check_service "artweb02p"             artweb02p
check_service "exporter → artweb01p"  nginx-exporter-artweb01p
check_service "exporter → artweb02p"  nginx-exporter-artweb02p
check_service "arthpx01p"             arthpx01p
check_service "artbdd01p"             artbdd01p
check_service "artbdd02p"             artbdd02p
check_service "agent → artbdd01p"     zabbix-agent-artbdd01p
check_service "agent → artbdd02p"     zabbix-agent-artbdd02p
check_service "exporter → artbdd01p"  postgres-exporter-artbdd01p
check_service "exporter → artbdd02p"  postgres-exporter-artbdd02p
check_service "artglptdb01p"           artglptdb01p
check_service "artglpt01p"             artglpt01p
check_service "agent → artglptdb01p"   zabbix-agent-artglptdb01p
check_service "agent → artglpt01p"     zabbix-agent-artglpt01p
check_service "artgradb01p"            artgradb01p
check_service "artgraidx01p"           artgraidx01p
check_service "artgra01p"              artgra01p
check_service "artspl01p"              artspl01p
check_service "artrsy01p"              artrsy01p
check_service "agent → artgradb01p"    zabbix-agent-artgradb01p
check_service "agent → artgraidx01p"   zabbix-agent-artgraidx01p
check_service "agent → artgra01p"      zabbix-agent-artgra01p
check_service "agent → artspl01p"      zabbix-agent-artspl01p
check_service "agent → artrsy01p"      zabbix-agent-artrsy01p
check_service "artsft02p"             artsft02p
check_service "agent → artsft02p"     zabbix-agent-artsft02p
check_service "artnfs01p"             artnfs01p
check_service "agent → artnfs01p"     zabbix-agent-artnfs01p
check_service "artbkp01p"             artbkp01p
check_service "agent → artbkp01p"     zabbix-agent-artbkp01p
check_service "agent → artweb01p"     zabbix-agent-artweb01p
check_service "agent → artweb02p"     zabbix-agent-artweb02p
check_service "agent → arthpx01p"     zabbix-agent-arthpx01p
check_service "artbbx01p"             artbbx01p
check_service "agent → artbbx01p"     zabbix-agent-artbbx01p
check_service "artmet01p"             artmet01p
check_service "agent → artmet01p"     zabbix-agent-artmet01p
check_service "artpgr01p"             artpgr01p
check_service "agent → artpgr01p"     zabbix-agent-artpgr01p
check_service "artgrf01p"             artgrf01p
check_service "agent → artgrf01p"     zabbix-agent-artgrf01p
check_service "artnag01p"             artnag01p
check_service "agent → artnag01p"     zabbix-agent-artnag01p

configure_graylog
configure_zabbix

# ── Récapitulatif des accès ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  Accès web et identifiants${RESET}"
echo -e "${DIM}  ──────────────────────────────────────────${RESET}"
printf "  %-18s %-36s %-24s%s\n" "Service" "URL" "Login" "Note"
print_access_row "HAProxy web" "http://localhost" "Aucun" "point d'entrée applicatif"
print_access_row "HAProxy stats" "http://localhost:8404/stats" "Aucun" "état frontend/backends"
print_access_row "Zabbix" "http://localhost:8080" "Admin / zabbix" "supervision agents"
print_access_row "Nagios" "http://localhost:8081/nagios" "nagiosadmin / nagios" "checks actifs"
print_access_row "GLPI" "http://localhost:8082" "glpi / glpi" "ITSM local"
print_access_row "Graylog" "http://localhost:9000" "admin / graylogadmin" "logs centralisés"
print_access_row "Splunk" "http://localhost:8000" "admin / splunkadmin" "recherche logs"
print_access_row "Prometheus" "http://localhost:9090" "Aucun" "métriques et targets"
print_access_row "Grafana" "http://localhost:3000" "admin / grafana" "dashboard Artemis"
echo ""
echo -e "${BOLD}  Accès logs / SIEM${RESET}"
echo -e "${DIM}  ──────────────────────────────────────────${RESET}"
echo -e "  Rsyslog TCP/UDP   ${CYAN}localhost:10514${RESET} → Graylog ${BOLD}1514${RESET} et Splunk ${BOLD}1515${RESET}"
echo -e "  Graylog GELF      ${CYAN}localhost:12201${RESET} TCP/UDP"
echo -e "  Splunk HEC        ${CYAN}http://localhost:8088/services/collector${RESET}"
echo -e "  HEC token         ${BOLD}00000000-0000-0000-0000-000000000000${RESET}"
echo ""
echo -e "${BOLD}  Accès fichiers${RESET}"
echo -e "${DIM}  ──────────────────────────────────────────${RESET}"
echo -e "  SFTP              ${CYAN}sftp -P 2222 artemis@localhost${RESET}"
echo -e "  Identifiants      utilisateur ${BOLD}artemis${RESET} / mot de passe ${BOLD}artemis${RESET}"
echo -e "  Répertoire        ${BOLD}/web${RESET} côté SFTP, monté depuis ${BOLD}./sftp/web${RESET}"
echo -e "  Sauvegarde        ${BOLD}artbkp01p${RESET} copie ${BOLD}./backup/source${RESET} vers SFTP et NFS toutes les 5 min"
echo ""
echo -e "${BOLD}  Initialisation Zabbix${RESET}"
echo -e "${DIM}  ──────────────────────────────────────────${RESET}"
echo -e "  Hosts et dashboard créés automatiquement par ${CYAN}./up.sh${RESET}"
echo -e "  Relance manuelle possible : ${CYAN}./zabbix/setup-hosts.sh && ./zabbix/setup-dashboard.py${RESET}"
echo ""
echo -e "${BOLD}  Commandes utiles${RESET}"
echo -e "${DIM}  ──────────────────────────────────────────${RESET}"
echo -e "  État des conteneurs     ${CYAN}docker compose ps${RESET}"
echo -e "  Logs d'un service       ${CYAN}docker compose logs <service>${RESET}"
echo -e "  Validation Compose      ${CYAN}docker compose config${RESET}"
echo -e "  Arrêt du lab            ${CYAN}./down.sh${RESET}"
echo -e "  Reset complet           ${CYAN}docker compose down -v${RESET}"
echo ""
