# Procédure — Lab de supervision Artemis

Ce lab simule l'infrastructure IT d'Artemis avec trois outils de supervision : **Zabbix**, **Nagios** et **Grafana + Prometheus**. Tout tourne dans Docker sur votre machine.

---

## Prérequis

- Docker Engine + compose installé et démarré
- Les ports suivants doivent être libres sur votre machine :

| Port | Usage |
|------|-------|
| 80 | HAProxy (trafic web) |
| 2222 | SFTP (sauvegarde web) |
| 3000 | Grafana |
| 8080 | Zabbix interface web |
| 8081 | Nagios interface web |
| 8404 | HAProxy statistiques |
| 9090 | Prometheus |
| 10051 | Zabbix server (traps) |

---

## Démarrage du lab

### Premier démarrage (ou après modification de la config)

```bash
./up.sh --build
```

L'option `--build` reconstruit les images Docker modifiées (nginx, haproxy). À faire systématiquement après tout changement de fichier de configuration.

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

> **Note :** Le démarrage complet prend environ 1 à 2 minutes. Si un service affiche `✗ ERREUR`, consultez ses logs avec `docker compose logs <nom-du-service>`.

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
| **Grafana** | http://localhost:3000 | `admin` | `grafana` |
| Prometheus | http://localhost:9090 | — | — |

### Upload SFTP

Le compte `artemis` peut écrire dans le dossier persistant `web`, stocké dans `sftp/web/` du dépôt et monté dans le conteneur.

```bash
sftp -P 2222 artemis@localhost
cd web
put ./mon-fichier.txt
```

---

## Configuration initiale de Zabbix (première fois uniquement)

Après le premier démarrage, Zabbix ne supervise aucun hôte. Lancez le script de configuration automatique :

```bash
./zabbix/setup-hosts.sh
./zabbix/setup-dashboard.py
```

Ce script crée les trois hôtes Artemis avec leurs templates et macros :

```
  Zabbix — Setup des hosts Artemis
  ──────────────────────────────────────────

  Authentification...          ✓
  Templates & groupes...       ✓
  artweb01p                    ✓  UP
  artweb02p                    ✓  UP
  arthpx01p                    ✓  UP
```

> **Important :** Ce script n'est nécessaire qu'au premier démarrage, ou si vous avez arrêté le lab avec `docker compose down -v` (suppression des volumes = perte de la base de données Zabbix).

### Vérification dans Zabbix

1. Ouvrez http://localhost:8080 → connexion avec `Admin` / `zabbix`
2. Menu **Monitoring → Hosts**
3. Les trois hôtes doivent apparaître avec le statut **ZBX** (agent) en vert

### Dashboard Zabbix

Un dashboard **"Artemis Supervision"** est créé dans Zabbix. Ouvrez **Dashboards → All dashboards → Artemis Supervision** pour suivre les problèmes courants, la disponibilité des agents, l'état HAProxy, le trafic HAProxy et les métriques CPU/RAM des backends web.

---

## Arrêt du lab

### Arrêt simple (données conservées)

```bash
docker compose down
```

Les données Zabbix sont conservées dans un volume Docker. Au prochain démarrage, pas besoin de relancer `setup-hosts.sh`.

### Arrêt complet avec remise à zéro

```bash
docker compose down -v
```

**Attention :** cette commande supprime toutes les données (base Zabbix, historique Grafana). Il faudra relancer `setup-hosts.sh` au prochain démarrage.

---

## Nagios — Ce qui est supervisé

Nagios vérifie automatiquement toutes les **minutes** :

| Hôte | Checks |
|------|--------|
| artweb01p | PING, HTTP (port 80), Nginx Status |
| artweb02p | PING, HTTP (port 80), Nginx Status |
| arthpx01p | PING, HTTP via HAProxy, HAProxy Stats (port 8404) |
| artsft02p | PING, SFTP TCP (port 22) |
| artnfs01p | PING, NFS TCP (port 2049) |

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
| **Nginx** | Connexions actives, requêtes/s, états des connexions |

> La datasource Prometheus est configurée automatiquement — aucune manipulation requise.

### Alertes Grafana

Une alerte provisionnée **"Artemis lab health problem"** est disponible dans **Alerting → Alert rules → Artemis**. Elle passe en alerte si le frontend HAProxy est down, si un backend Nginx est down côté HAProxy, si une cible Prometheus est down, si un probe Blackbox HTTP/SFTP/NFS échoue, ou si HAProxy retourne des erreurs HTTP 5xx.

---

## Zabbix — Templates appliqués

| Hôte | Templates |
|------|-----------|
| artweb01p | Linux by Zabbix agent + Nginx by Zabbix agent |
| artweb02p | Linux by Zabbix agent + Nginx by Zabbix agent |
| arthpx01p | Linux by Zabbix agent + HAProxy by HTTP |

Le template **HAProxy by HTTP** collecte les métriques via la page de stats CSV de HAProxy (port 8406), sans passer par l'agent.

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
