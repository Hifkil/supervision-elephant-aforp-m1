# Lab de supervision Artemis

Ce dépôt contient un lab Docker pour superviser une infrastructure Artemis avec **Zabbix**, **Nagios** et **Grafana + Prometheus**.

Le lab simule une entrée web HAProxy, deux backends Nginx, des services de fichiers SFTP/NFS et une chaîne de supervision complète. Il sert de support pratique pour tester les checks, dashboards, alertes et seuils d'exploitation.

## Contenu du dépôt

| Chemin | Rôle |
|--------|------|
| `docker-compose.yml` | Stack complète du lab |
| `nginx/` | Configuration et image des backends web |
| `haproxy/` | Configuration et image du load balancer |
| `prometheus/` | Configuration des scrape targets Prometheus |
| `blackbox/` | Probes HTTP, TCP et ICMP |
| `nagios/` | Checks Nagios des hôtes Artemis |
| `grafana/provisioning/` | Datasource, dashboard et alerte Grafana |
| `zabbix/` | Scripts et exports de configuration Zabbix |
| `sftp/` | Initialisation et volume web SFTP |
| `Sujet/` | Documents sources du brief et du cours |
| `PROCEDURE.md` | Procédure détaillée de démarrage, accès et dépannage |
| `SUPERVISION_THRESHOLDS.md` | Seuils de supervision et logique d'alerte |

## Prérequis

- Docker Engine installé et démarré
- Docker Compose disponible via `docker compose`
- Ports locaux libres : `80`, `2222`, `3000`, `8080`, `8081`, `8404`, `9090`, `10051`

## Démarrage rapide

Premier lancement, ou après modification d'une configuration :

```bash
./up.sh --build
```

Lancements suivants, sans rebuild :

```bash
./up.sh
```

Configuration initiale de Zabbix après le premier démarrage :

```bash
./zabbix/setup-hosts.sh
./zabbix/setup-dashboard.py
```

Arrêt simple, avec conservation des volumes :

```bash
./down.sh
```

Remise à zéro complète des données :

```bash
docker compose down -v
```

## Accès aux interfaces

| Service | URL | Identifiants |
|---------|-----|--------------|
| HAProxy | http://localhost | Aucun |
| HAProxy stats | http://localhost:8404/stats | Aucun |
| Zabbix | http://localhost:8080 | `Admin` / `zabbix` |
| Nagios | http://localhost:8081/nagios | `nagiosadmin` / `nagios` |
| Grafana | http://localhost:3000 | `admin` / `grafana` |
| Prometheus | http://localhost:9090 | Aucun |
| SFTP | `sftp -P 2222 artemis@localhost` | `artemis` / `artemis` |

## Architecture simulée

```text
Internet
    |
    v
arthpx01p  HAProxy
    |-- artweb01p  Nginx backend 1
    `-- artweb02p  Nginx backend 2

Services fichiers
    |-- artsft02p  SFTP
    `-- artnfs01p  NFS

Supervision
    |-- artzab01p     Zabbix Server
    |-- artzabweb01p  Interface web Zabbix
    |-- artdb01p      Base PostgreSQL Zabbix
    |-- artnag01p     Nagios
    |-- artprom01p    Prometheus
    |-- artgrf01p     Grafana
    `-- artbbx01p     Blackbox Exporter
```

## Ce qui est supervisé

- Disponibilité HTTP des backends Nginx et du frontend HAProxy
- Statut HAProxy et état des backends
- Disponibilité SFTP et NFS
- Probes HTTP, TCP et ICMP via Blackbox Exporter
- Métriques Linux via agents Zabbix
- Métriques Nginx, HAProxy et targets Prometheus
- Dashboard Grafana **Artemis Supervision**
- Dashboard Zabbix **Artemis Supervision**
- Alerte Grafana consolidée **Artemis lab health problem**

Les seuils fonctionnels sont documentés dans `SUPERVISION_THRESHOLDS.md`.

## Validation

Avant de publier ou modifier le lab :

```bash
docker compose config
./up.sh --build
```

Après démarrage, vérifiez les interfaces principales :

- HAProxy : http://localhost
- Zabbix : http://localhost:8080
- Nagios : http://localhost:8081/nagios
- Prometheus : http://localhost:9090
- Grafana : http://localhost:3000

## Documentation

Consultez `PROCEDURE.md` pour la procédure complète : démarrage, accès, configuration Zabbix, dashboards, arrêt et dépannage.

Consultez `SUPERVISION_THRESHOLDS.md` pour la définition des métriques, seuils `WARNING` et seuils `CRITICAL`.

## Notes de publication GitHub

Les fichiers `AGENTS.md` et `CLAUDE.md` contiennent du contexte local pour les assistants de développement et ne sont pas destinés à être publiés dans le dépôt GitHub.

Les données générées, volumes Docker, caches locaux et secrets réels ne doivent pas être versionnés.
