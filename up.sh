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

TIMEOUT=240   # secondes max d'attente par service (zabbix-web ~2-3 min)
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

# ── Vérification dans l'ordre de démarrage ────────────────────────────────────
echo -e "${BOLD}  État des services${RESET}"
echo -e "${DIM}  ──────────────────────────────────────────${RESET}"

check_service "artdb01p"              artdb01p
check_service "artzab01p"             artzab01p
check_service "agent → artzab01p"     zabbix-agent-artzab01p
check_service "artzabweb01p"          artzabweb01p
check_service "artweb01p"             artweb01p
check_service "artweb02p"             artweb02p
check_service "arthpx01p"             arthpx01p
check_service "artsft02p"             artsft02p
check_service "artnfs01p"             artnfs01p
check_service "agent → artweb01p"     zabbix-agent-artweb01p
check_service "agent → artweb02p"     zabbix-agent-artweb02p
check_service "agent → arthpx01p"     zabbix-agent-arthpx01p
check_service "artprom01p"            artprom01p
check_service "artgrf01p"             artgrf01p
check_service "artnag01p"             artnag01p

# ── Récapitulatif des accès ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  Accès${RESET}"
echo -e "${DIM}  ──────────────────────────────────────────${RESET}"
echo -e "  HAProxy  (web)    ${CYAN}http://localhost${RESET}"
echo -e "  HAProxy  (stats)  ${CYAN}http://localhost:8404/stats${RESET}"
echo -e "  SFTP              ${CYAN}sftp://localhost:2222${RESET} ${DIM}(artemis/artemis)${RESET}"
echo -e "  Zabbix            ${CYAN}http://localhost:8080${RESET}"
echo -e "  Nagios            ${CYAN}http://localhost:8081/nagios${RESET}
  Prometheus        ${CYAN}http://localhost:9090${RESET}
  Grafana           ${CYAN}http://localhost:3000${RESET}"
echo ""
echo -e "  ${BOLD}Login Zabbix${RESET}"
echo -e "    Utilisateur   ${BOLD}Admin${RESET}  /  Mot de passe  ${BOLD}zabbix${RESET}"
echo -e "  ${BOLD}Login Nagios${RESET}"
echo -e "    Utilisateur   ${BOLD}nagiosadmin${RESET}  /  Mot de passe  ${BOLD}nagios${RESET}"
echo -e "  ${BOLD}Login Grafana${RESET}"
echo -e "    Utilisateur   ${BOLD}admin${RESET}  /  Mot de passe  ${BOLD}grafana${RESET}"
echo ""
