# Procédure — Lab de supervision Artemis

Ce lab simule l'infrastructure IT d'Artemis avec trois outils de supervision : **Zabbix**, **Nagios** et **Grafana + Prometheus**, plus une brique logs/SIEM **Graylog + Rsyslog + Splunk**. Tout tourne dans Docker sur votre machine.

---

## Prérequis

- Docker Engine + compose installé et démarré
- Les ports suivants doivent être libres sur votre machine :

| Port | Usage |
|------|-------|
| 80 | HAProxy (trafic web) |
| 1514 | Graylog Syslog TCP/UDP |
| 1515 | Splunk Syslog TCP |
| 2222 | SFTP (sauvegarde web) |
| 3000 | Grafana |
| 8000 | Splunk interface web |
| 8080 | Zabbix interface web |
| 8081 | Nagios interface web |
| 8082 | GLPI |
| 8088 | Splunk HEC |
| 8404 | HAProxy statistiques |
| 9000 | Graylog interface web/API |
| 9090 | Prometheus |
| 10051 | Zabbix server (traps) |
| 10514 | Rsyslog syslog TCP/UDP côté hôte |
| 12201 | Graylog GELF TCP/UDP |

Graylog s'appuie sur OpenSearch. Vérifiez que l'hôte Docker expose au moins `262144` pour `vm.max_map_count` :

```bash
cat /proc/sys/vm/max_map_count
```

---

## Démarrage du lab

### Premier démarrage (ou après modification de la config)

```bash
./up.sh --build
```

L'option `--build` reconstruit les images Docker modifiées (nginx, haproxy, rsyslog). À faire systématiquement après tout changement de fichier de configuration.

### Démarrages suivants (sans changement)

```bash
./up.sh
```

Le script affiche l'état de chaque service et les URLs d'accès :

```
  État des services
  ──────────────────────────────────────────
  artdb01p                     ✓  UP (0s)
  artzab01p                    ✓  UP (16s)
  agent → artzab01p            ✓  UP (0s)
  artzabweb01p                 ✓  UP (6s)
  artweb01p                    ✓  UP (0s)
  artweb02p                    ✓  UP (0s)
  arthpx01p                    ✓  UP (0s)
  ...
```

> **Note :** Le démarrage complet prend environ 3 à 5 minutes à cause de Graylog/OpenSearch et Splunk. Si un service affiche `✗ ERREUR`, consultez ses logs avec `docker compose logs <nom-du-service>`.

---

## Infrastructure simulée

```
Internet
    │
    ▼
arthpx01p (HAProxy — load balancer)
    ├──► artweb01p (Nginx — backend web 1)
    └──► artweb02p (Nginx — backend web 2)

Services fichiers
    ├── artsft02p  SFTP (sauvegarde /web)
    └── artnfs01p  NFS  (sauvegarde /web)

Base de données
    ├── artbdd01p  PostgreSQL primaire
    └── artbdd02p  PostgreSQL réplique

ITSM
    ├── artglpt01p    GLPI
    └── artglptdb01p  Base MySQL dédiée GLPI

Logs / SIEM
    ├── artrsy01p      Rsyslog collecteur et relais
    ├── artgry01p      Graylog
    ├── artgrydb01p    MongoDB Graylog
    ├── artgryidx01p   OpenSearch Graylog
    └── artspl01p      Splunk

Supervision
    ├── artzab01p   Zabbix Server
    ├── artzabweb01p Zabbix Interface web
    ├── artdb01p    Base de données Zabbix (PostgreSQL)
    ├── artnag01p   Nagios
    ├── artprom01p  Prometheus
    ├── artgrf01p   Grafana
    └── artbbx01p   Blackbox Exporter (probes HTTP/ICMP)
```

Chaque serveur supervisé possède un **agent Zabbix sidecar** qui collecte les métriques système.

---

## Accès aux interfaces

| Outil | URL | Utilisateur | Mot de passe |
|-------|-----|-------------|--------------|
| HAProxy (web) | http://localhost | — | — |
| HAProxy (stats) | http://localhost:8404/stats | — | — |
| **SFTP** | `sftp -P 2222 artemis@localhost` | `artemis` | `artemis` |
| **Zabbix** | http://localhost:8080 | `Admin` | `zabbix` |
| **Nagios** | http://localhost:8081/nagios | `nagiosadmin` | `nagios` |
| **GLPI** | http://localhost:8082 | `glpi` | `glpi` |
| **Graylog** | http://localhost:9000 | `admin` | `graylogadmin` |
| **Splunk** | http://localhost:8000 | `admin` | `splunkadmin` |
| **Grafana** | http://localhost:3000 | `admin` | `grafana` |
| Prometheus | http://localhost:9090 | — | — |
| Rsyslog | `localhost:10514` TCP/UDP | — | — |
| Splunk HEC | http://localhost:8088/services/collector | token | `00000000-0000-0000-0000-000000000000` |

GLPI utilise `artglptdb01p`, une base MySQL dédiée. Les bases déjà présentes dans le lab sont en PostgreSQL et restent réservées à Artemis et Zabbix.

### Logs / SIEM

`artrsy01p` lit les logs JSON Docker de tous les conteneurs du lab via `/var/lib/docker/containers`, écoute aussi du syslog TCP/UDP sur `localhost:10514`, puis transfère vers :

- Graylog `artgry01p:1514` avec les inputs **Artemis syslog TCP/UDP** créés par `./graylog/setup-inputs.sh`
- Splunk `artspl01p:1515` dans l'index `artemis`

Recherche rapide Splunk :

```text
index=artemis
```

### Upload SFTP

Le compte `artemis` peut écrire dans le dossier persistant `web`, stocké dans `sftp/web/` du dépôt et monté dans le conteneur.

```bash
sftp -P 2222 artemis@localhost
cd web
put ./mon-fichier.txt
```

---

## Configuration initiale de Zabbix

Après le démarrage, `./up.sh` lance automatiquement les scripts de configuration Zabbix :

```bash
./zabbix/setup-hosts.sh
./zabbix/setup-dashboard.py
```

Ces scripts restent relançables manuellement si besoin. Ils créent les hôtes Artemis avec leurs templates et macros :

```
  Zabbix — Setup des hosts Artemis
  ──────────────────────────────────────────

  Authentification...          ✓
  Templates & groupes...       ✓
  artzab01p                    ✓  UP
  artweb01p                    ✓  UP
  artweb02p                    ✓  UP
  arthpx01p                    ✓  UP
```

> **Important :** après `docker compose down -v`, `./up.sh` recrée automatiquement les hosts et le dashboard Zabbix.

### Vérification dans Zabbix

1. Ouvrez http://localhost:8080 → connexion avec `Admin` / `zabbix`
2. Menu **Monitoring → Hosts**
3. Les hôtes Artemis doivent apparaître avec le statut **ZBX** (agent) en vert

### Dashboard Zabbix

Un dashboard **"Artemis Supervision"** est créé dans Zabbix. Ouvrez **Dashboards → All dashboards → Artemis Supervision** pour suivre les problèmes courants, la disponibilité des agents, les statuts applicatifs, HAProxy/Nginx, GLPI, SIEM/logs, CPU/RAM par tiers, réseau, latence PostgreSQL et santé de la pile de supervision.

---

## Arrêt du lab

### Arrêt simple (données conservées)

```bash
docker compose down
```

Les données Zabbix sont conservées dans un volume Docker. Au prochain démarrage, `./up.sh` vérifie et met à jour la configuration automatiquement.

### Arrêt complet avec remise à zéro

```bash
docker compose down -v
```

**Attention :** cette commande supprime toutes les données (base Zabbix, historique Grafana). `./up.sh` recréera la configuration Zabbix au prochain démarrage.

---

## Nagios — Ce qui est supervisé

Nagios vérifie automatiquement toutes les **minutes** :

| Hôte | Checks |
|------|--------|
| artweb01p | PING, HTTP, contenu HTTP, Nginx Status, Nginx exporter |
| artweb02p | PING, HTTP, contenu HTTP, Nginx Status, Nginx exporter |
| arthpx01p | PING, HTTP via HAProxy, contenu HTTP, stats HAProxy, métriques Prometheus HAProxy, CSV Zabbix |
| artsft02p | PING, SFTP TCP (port 22) |
| artnfs01p | PING, NFS TCP (port 2049) |
| artbdd01p | PING, PostgreSQL TCP, exporter `pg_up`, rôle primaire, flux de réplication |
| artbdd02p | PING, PostgreSQL TCP, exporter `pg_up`, rôle réplique, métrique de lag |
| artdb01p | PING, PostgreSQL TCP de la base Zabbix |
| artglpt01p / artglptdb01p | PING, HTTP GLPI, contenu HTTP, MySQL TCP |
| artgrydb01p / artgryidx01p / artgry01p | PING, MongoDB TCP, OpenSearch HTTP, Graylog API, Graylog Syslog TCP |
| artspl01p / artrsy01p | PING, Splunk Web, Splunk HEC, Splunk Syslog TCP, Rsyslog TCP |
| artzab01p / artzabweb01p | PING, port serveur Zabbix, endpoint `/ping` web |
| artbkp01p | PING, endpoint métriques backup, compteur de fichiers copiés |
| artbbx01p / artmet01p | PING, métriques Blackbox, métriques Docker et volumes |
| artprom01p / artgrf01p / artnag01p | PING, santé Prometheus, API Grafana, interface Nagios |

Accédez aux résultats : http://localhost:8081/nagios → **Services**

---

## Grafana — Dashboard Artemis

Le dashboard **"Artemis Supervision"** est pré-configuré et se charge automatiquement.

1. Ouvrez http://localhost:3000 → connexion avec `admin` / `grafana`
2. Menu **Dashboards** → dossier **Artemis** → **Artemis Supervision**

Le dashboard contient :

| Section | Ce qu'on voit |
|---------|---------------|
| **HAProxy** | Statut artweb01p / artweb02p, sessions actives, taux de requêtes HTTP, trafic réseau |
| **Connectivité backends** | Disponibilité HTTP + Ping ICMP, latence en ms |
| **Services fichiers** | Disponibilité TCP SFTP/NFS via Blackbox |
| **GLPI** | Disponibilité HTTP de GLPI, disponibilité TCP de sa base MySQL et latence |
| **Logs / SIEM** | Disponibilité Graylog, Rsyslog, Splunk, ports d'ingestion et latence |
| **Base de données** | Disponibilité PostgreSQL, exporter PostgreSQL, activité de la base Artemis |
| **Nginx** | Connexions actives, requêtes/s, états des connexions |
| **Système** | État, CPU, RAM, réseau et I/O disque de tous les conteneurs Compose |
| **Disque** | Occupation des volumes Docker |

> La datasource Prometheus est configurée automatiquement — aucune manipulation requise.

### Alertes Grafana

Les alertes provisionnées sont disponibles dans **Alerting → Alert rules → Artemis**. Elles sont séparées par domaine : frontend HAProxy, backends web, GLPI, SIEM/logs, services fichiers, base de données PostgreSQL, sauvegarde, capacité plateforme et pile de supervision.

---

## Zabbix — Templates appliqués

| Hôte | Templates |
|------|-----------|
| artweb01p | Linux by Zabbix agent + Nginx by Zabbix agent |
| artweb02p | Linux by Zabbix agent + Nginx by Zabbix agent |
| arthpx01p | Linux by Zabbix agent + HAProxy by HTTP |
| artbdd01p / artbdd02p | Linux by Zabbix agent |
| artglpt01p / artglptdb01p | Linux by Zabbix agent |
| artgrydb01p / artgryidx01p / artgry01p / artspl01p / artrsy01p | Linux by Zabbix agent |
| artsft02p / artnfs01p / artbkp01p | Linux by Zabbix agent |
| artprom01p / artgrf01p / artnag01p / artbbx01p / artmet01p | Linux by Zabbix agent |

Le template **HAProxy by HTTP** collecte les métriques via la page de stats CSV de HAProxy (port 8406), sans passer par l'agent.

Des items Zabbix supplémentaires sont créés par `setup-hosts.sh` pour les checks applicatifs simples : ports PostgreSQL, GLPI/MySQL, SIEM/logs, SFTP/NFS, endpoint backup, Prometheus, Grafana, Nagios, Blackbox et exporter Docker. Ils alimentent les widgets de statut et les graphes de latence du dashboard Zabbix.

---

## Dépannage

### Un service affiche `✗ ERREUR` au démarrage

```bash
docker compose logs <nom-du-service>
```

### Zabbix affiche un hôte "Not available"

Attendez 2-3 minutes après le démarrage — les agents ont besoin de temps pour s'enregistrer. Si le problème persiste :

```bash
docker compose restart zabbix-agent-<nom-hôte>
```

### Le dashboard Grafana est vide

Prometheus met ~15 secondes à collecter les premières métriques. Rafraîchissez la page après le démarrage complet.

### Alertes "System name has changed" dans Zabbix

Ces alertes apparaissent après un redémarrage complet — elles se résolvent automatiquement en quelques minutes quand Zabbix détecte que le hostname est stable.

### Tout relancer proprement

```bash
docker compose down && ./up.sh --build
```

C'est la commande de référence après n'importe quelle modification de configuration.
