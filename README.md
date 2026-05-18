# Lab de supervision Artemis

Ce dépôt contient un lab Docker pour superviser une infrastructure Artemis avec **Zabbix**, **Nagios** et **Grafana + Prometheus**.

Le lab simule une entrée web HAProxy, deux backends Nginx, un cluster PostgreSQL primaire/réplique, des services de fichiers SFTP/NFS et une chaîne de supervision complète. Il sert de support pratique pour tester les checks, dashboards, alertes et seuils d'exploitation.

## Contenu du dépôt

| Chemin | Rôle |
|--------|------|
| `docker-compose.yml` | Stack complète du lab |
| `nginx/` | Configuration et image des backends web |
| `haproxy/` | Configuration et image du load balancer |
| `postgres/` | Scripts de réplication PostgreSQL primaire/réplique |
| `prometheus/` | Configuration des scrape targets Prometheus |
| `blackbox/` | Probes HTTP, TCP et ICMP |
| `nagios/` | Checks Nagios des hôtes Artemis |
| `grafana/provisioning/` | Datasource, dashboard et alerte Grafana |
| `zabbix/` | Scripts de bootstrap de configuration Zabbix |
| `sftp/` | Initialisation et volume web SFTP |
| `backup/` | Payload source copié vers SFTP et NFS pour tester la supervision de sauvegarde |
| `docker-metrics/` | Exporter léger des métriques CPU/RAM/réseau/disque par conteneur |
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

`./up.sh` initialise automatiquement les hosts et le dashboard Zabbix après le démarrage de l'interface web.

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
    |-- artnfs01p  NFS
    `-- artbkp01p  Sauvegarde web simple

Base de données
    |-- artbdd01p  PostgreSQL primaire
    `-- artbdd02p  PostgreSQL réplique

Supervision
    |-- artzab01p     Zabbix Server
    |-- artzabweb01p  Interface web Zabbix
    |-- artdb01p      Base PostgreSQL Zabbix
    |-- artnag01p     Nagios
    |-- artprom01p    Prometheus
    |-- artgrf01p     Grafana
    |-- artbbx01p     Blackbox Exporter
    `-- artmet01p     Exporter métriques Docker
```

## Ce qui est supervisé

- Disponibilité HTTP des backends Nginx et du frontend HAProxy
- Statut HAProxy et état des backends
- Disponibilité SFTP et NFS
- Disponibilité PostgreSQL primaire/réplique
- Probes HTTP, TCP et ICMP via Blackbox Exporter
- Métriques Linux via agents Zabbix
- Checks Zabbix applicatifs : ports PostgreSQL, SFTP/NFS, backup, Prometheus, Grafana, Nagios, Blackbox et exporter Docker
- Métriques système Docker via `artmet01p` : CPU, RAM, réseau et I/O disque par conteneur
- Métriques Nginx, HAProxy, PostgreSQL et targets Prometheus
- Checks Nagios enrichis : contenus HTTP, exporters, rôles PostgreSQL primaire/réplique, métriques backup et santé de la pile de supervision
- Occupation disque des volumes Docker
- Sauvegarde simple de `backup/source` vers SFTP et NFS, avec métriques de fraîcheur et de statut
- Dashboard Grafana **Artemis Supervision**
- Dashboard Zabbix **Artemis Supervision**
- Alertes Grafana séparées par domaine fonctionnel

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
