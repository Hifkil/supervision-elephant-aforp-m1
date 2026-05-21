# Dossier d'exploitation - Artemis

Version : 1.0  
Date : 2026-05-21  
Support : maquette Docker Compose `supervision-elephant-aforp-m1`

## 1. Objet du document

Ce DEX décrit l'exploitation courante de la maquette Artemis : démarrage, arrêt, accès aux interfaces, supervision, sauvegarde, contrôles de santé, procédures de dépannage et scénarios de panne.

Le périmètre est volontairement adapté à une maquette étudiante. Le deuxième HAProxy, la VIP, la segmentation VLAN, le SMTP `artsmt01p` et l'annuaire `artann01p` ne sont pas simulés. Les notifications mail et l'intégration annuaire sont également hors périmètre.

## 2. Vue d'ensemble

La stack tourne sur Docker Compose avec un réseau bridge unique `artemis`. Chaque conteneur représente une machine Artemis ou un composant technique nécessaire à la supervision.

```text
Client
  |
  v
arthpx01p  HAProxy
  |-- artweb01p  Nginx backend 1
  `-- artweb02p  Nginx backend 2

Services fichiers
  |-- artsft02p  SFTP
  |-- artnfs01p  NFS
  `-- artbkp01p  copie de sauvegarde vers SFTP et NFS

Base de donnees Artemis
  |-- artbdd01p  PostgreSQL primaire
  `-- artbdd02p  PostgreSQL replique

ITSM
  |-- artglpt01p    GLPI
  `-- artglptdb01p  MySQL GLPI

Logs / SIEM
  |-- artrsy01p      Rsyslog collecteur
  |-- artgra01p      Graylog
  |-- artgradb01p    MongoDB Graylog
  |-- artgraidx01p   OpenSearch Graylog
  `-- artspl01p      Splunk

Supervision
  |-- artzab01p     Zabbix Server
  |-- artzabweb01p  Zabbix Web
  |-- artdb01p      PostgreSQL Zabbix
  |-- artnag01p     Nagios
  |-- artpgr01p     Prometheus
  |-- artgrf01p     Grafana
  |-- artbbx01p     Blackbox Exporter
  `-- artmet01p     Exporter metriques Docker
```

## 3. Prerequis d'exploitation

| Prerequis | Valeur attendue |
|---|---|
| Docker | Docker Engine actif |
| Compose | Commande `docker compose` disponible |
| Systeme | Linux recommande pour OpenSearch et NFS |
| OpenSearch | `vm.max_map_count >= 262144` |
| Repertoire de travail | Racine du depot |

Verification OpenSearch :

```bash
cat /proc/sys/vm/max_map_count
```

Si la valeur est trop basse :

```bash
sudo sysctl -w vm.max_map_count=262144
```

## 4. Commandes d'exploitation

| Action | Commande |
|---|---|
| Valider la syntaxe Compose | `docker compose config --quiet` |
| Premier demarrage ou rebuild | `./up.sh --build` |
| Demarrage standard | `./up.sh` |
| Etat des conteneurs | `docker compose ps` |
| Logs d'un service | `docker compose logs -f <service>` |
| Redemarrer un service | `docker compose restart <service>` |
| Arret avec conservation des volumes | `./down.sh` |
| Arret Compose equivalent | `docker compose down` |
| Reset complet des donnees | `docker compose down -v` |

`./up.sh` demarre la stack, recree les sidecars reseau sensibles, attend les services principaux, initialise Graylog et initialise Zabbix.

Sidecars recrees automatiquement au demarrage :

- `zabbix-agent-*`
- `nginx-exporter-*`
- `postgres-exporter-*`

Cette recreation evite les erreurs de type `Connection refused` apres redemarrage d'une machine simulee.

## 5. Acces aux interfaces

| Service | URL / commande | Identifiants |
|---|---|---|
| HAProxy web | http://localhost | Aucun |
| HAProxy stats | http://localhost:8404/stats | Aucun |
| Zabbix | http://localhost:8080 | `Admin` / `zabbix` |
| Nagios | http://localhost:8081/nagios | `nagiosadmin` / `nagios` |
| GLPI | http://localhost:8082 | `glpi` / `glpi` |
| Graylog | http://localhost:9000 | `admin` / `graylogadmin` |
| Splunk | http://localhost:8000 | `admin` / `splunkadmin` |
| Grafana | http://localhost:3000 | `admin` / `grafana` |
| Prometheus | http://localhost:9090 | Aucun |
| SFTP | `sftp -P 2222 artemis@localhost` | `artemis` / `artemis` |
| Rsyslog | `localhost:10514` TCP/UDP | Collecte syslog |
| Splunk HEC | http://localhost:8088/services/collector | token `00000000-0000-0000-0000-000000000000` |

Les mots de passe sont des identifiants de lab local. Ils ne doivent pas etre reutilises hors maquette.

## 6. Ports exposes

| Port hote | Service | Usage |
|---:|---|---|
| 80 | `arthpx01p` | Entree web HAProxy |
| 1514 | `artgra01p` | Syslog Graylog TCP/UDP |
| 1515 | `artspl01p` | Syslog Splunk TCP |
| 2222 | `artsft02p` | SFTP |
| 3000 | `artgrf01p` | Grafana |
| 8000 | `artspl01p` | Splunk Web |
| 8080 | `artzabweb01p` | Zabbix Web |
| 8081 | `artnag01p` | Nagios |
| 8082 | `artglpt01p` | GLPI |
| 8088 | `artspl01p` | Splunk HEC |
| 8404 | `arthpx01p` | HAProxy stats HTML |
| 8405 | `arthpx01p` | HAProxy metrics Prometheus |
| 8406 | `arthpx01p` | HAProxy stats CSV pour Zabbix |
| 9000 | `artgra01p` | Graylog Web/API |
| 9090 | `artpgr01p` | Prometheus |
| 10051 | `artzab01p` | Zabbix server |
| 10514 | `artrsy01p` | Syslog local TCP/UDP |
| 12201 | `artgra01p` | GELF Graylog TCP/UDP |

## 7. Donnees persistantes

| Volume / chemin | Usage |
|---|---|
| `zabbix-db` | Base PostgreSQL Zabbix |
| `artbdd01p-data` | Donnees PostgreSQL primaire Artemis |
| `artbdd02p-data` | Donnees PostgreSQL replique Artemis |
| `grafana-data` | Donnees Grafana |
| `prometheus-data` | TSDB Prometheus |
| `glpi-data` | Fichiers GLPI |
| `glpi-db` | Base MySQL GLPI |
| `graylog-*` | Donnees Graylog, MongoDB et OpenSearch |
| `splunk-data` | Donnees Splunk |
| `rsyslog-spool` | File d'attente Rsyslog |
| `./sftp/web` | Repertoire SFTP persistant |
| `nfs-web` | Donnees exposees par NFS |
| `./backup/source` | Source de la sauvegarde de demonstration |

Reset complet :

```bash
docker compose down -v
```

Cette commande supprime les volumes Docker. Elle remet a zero les donnees Zabbix, Prometheus, Grafana, GLPI, Graylog, Splunk et PostgreSQL.

## 8. Demarrage nominal

Procedure :

```bash
docker compose config --quiet
./up.sh
docker compose ps
```

Etat attendu :

- les services principaux sont `Up` ;
- les services avec healthcheck sont `healthy` ;
- Prometheus repond `Prometheus Server is Healthy.` ;
- Graylog repond `ALIVE` sur `/api/system/lbstatus` ;
- l'agent Zabbix d'un hote de test repond `1`.

Commandes de controle :

```bash
curl -fsS http://localhost
curl -fsS http://localhost:9090/-/healthy
curl -fsS http://localhost:9000/api/system/lbstatus
curl -fsS http://localhost:3000/api/health
docker compose exec -T artzab01p zabbix_get -s artweb01p -k agent.ping
```

## 9. Arret et reprise

Arret simple :

```bash
./down.sh
```

Reprise :

```bash
./up.sh
```

Apres reprise, attendre 1 a 3 minutes pour que Zabbix, Nagios et Prometheus stabilisent leurs etats.

Si un sidecar reste indisponible apres redemarrage d'un service :

```bash
docker compose up -d --force-recreate --no-deps <sidecar>
```

Exemples :

```bash
docker compose up -d --force-recreate --no-deps zabbix-agent-artweb01p
docker compose up -d --force-recreate --no-deps nginx-exporter-artweb01p
docker compose up -d --force-recreate --no-deps postgres-exporter-artbdd02p
```

## 10. Exploitation Zabbix

Zabbix sert de vue d'exploitation centrale :

- disponibilite des agents ;
- metriques systeme Linux ;
- ports applicatifs ;
- checks simples GLPI, PostgreSQL, SIEM, SFTP/NFS, backup, Prometheus, Grafana, Nagios ;
- dashboard `Artemis Supervision`.

Initialisation automatique par `./up.sh` :

```bash
./zabbix/setup-hosts.sh
./zabbix/setup-dashboard.py
```

Relance manuelle si besoin :

```bash
./zabbix/setup-hosts.sh
./zabbix/setup-dashboard.py
```

Verification rapide d'un agent :

```bash
docker compose exec -T artzab01p zabbix_get -s artweb01p -k agent.ping
```

Resultat attendu : `1`.

## 11. Exploitation Nagios

Nagios donne une vue active et lisible des etats `OK`, `WARNING`, `CRITICAL`, `UNKNOWN`.

Acces :

```text
http://localhost:8081/nagios
```

Verification de configuration :

```bash
docker compose exec -T artnag01p nagios -v /opt/nagios/etc/nagios.cfg
```

Checks principaux :

| Domaine | Checks |
|---|---|
| Web | PING, HTTP, contenu HTTP, Nginx status, exporter Nginx |
| HAProxy | HTTP, contenu, stats, metrics, CSV |
| Base Artemis | PostgreSQL TCP, exporter `pg_up`, role primaire/replique, lag |
| GLPI | HTTP GLPI, contenu, MySQL TCP |
| Fichiers | SFTP TCP, NFS TCP, backup metrics |
| Logs/SIEM | Rsyslog, Graylog API/Syslog, MongoDB, OpenSearch, Splunk Web/HEC/Syslog |
| Supervision | Prometheus, Grafana, Zabbix, Nagios, Blackbox, Docker metrics |

## 12. Exploitation Prometheus et Grafana

Prometheus collecte :

- metriques HAProxy ;
- metriques Nginx ;
- metriques PostgreSQL ;
- probes HTTP/TCP/ICMP Blackbox ;
- metriques Docker via `artmet01p` ;
- metriques backup via `artbkp01p`.

Acces targets :

```text
http://localhost:9090/targets
```

Grafana :

```text
http://localhost:3000
```

Dashboard :

```text
Dashboards -> Artemis -> Artemis Supervision
```

Les alertes Grafana sont provisionnees par domaine. Le routage mail n'est pas configure volontairement.

## 13. Exploitation logs / SIEM

Flux nominal :

```text
logs Docker + syslog local
  -> artrsy01p
  -> Graylog artgra01p:1514
  -> Splunk artspl01p:1515
```

Rsyslog ecoute aussi sur l'hote :

```text
localhost:10514 TCP/UDP
```

Envoyer un log de test :

```bash
logger -n 127.0.0.1 -P 10514 -T "artemis test exploitation"
```

Graylog :

- URL : http://localhost:9000
- recherche dans les messages entrants Syslog Artemis.

Splunk :

- URL : http://localhost:8000
- recherche rapide :

```text
index=artemis
```

## 14. Sauvegarde

La sauvegarde est une preuve technique locale, pas une politique de sauvegarde de production.

Service :

```text
artbkp01p
```

Fonctionnement :

- source : `./backup/source` ;
- destination SFTP : `./sftp/web` ;
- destination NFS : volume `nfs-web` ;
- intervalle : 300 secondes ;
- endpoint metriques : `artbkp01p:8080/metrics`.

Verification :

```bash
docker compose exec -T artbkp01p wget -qO- http://localhost:8080/metrics
```

Metriques attendues :

- `artemis_backup_last_status 0` ;
- `artemis_backup_copied_files` superieur a `0` ;
- `artemis_backup_last_success_timestamp_seconds` recent.

Les fichiers `LAST_BACKUP_UTC.txt` sont ecrits dans les destinations SFTP et NFS apres une sauvegarde reussie.

## 15. Scenarios de panne

Le script `run-scenario.sh` permet de rejouer trois incidents de demonstration.

Afficher les URLs :

```bash
./run-scenario.sh urls
```

Afficher l'etat :

```bash
./run-scenario.sh status
```

Scenarios :

| Scenario | Injection | Restauration | Ce que l'on demontre |
|---|---|---|---|
| Perte d'un backend web | `./run-scenario.sh web-down` | `./run-scenario.sh web-restore` | HAProxy continue via `artweb02p` et la supervision detecte `artweb01p` down |
| Perte de la replique PostgreSQL | `./run-scenario.sh db-down` | `./run-scenario.sh db-restore` | Le primaire reste disponible et la replique est detectee down |
| Perte du collecteur logs | `./run-scenario.sh siem-down` | `./run-scenario.sh siem-restore` | Graylog/Splunk restent accessibles mais le relais Rsyslog est coupe |

Retour global :

```bash
./run-scenario.sh restore-all
```

Les checks Nagios, Zabbix et Prometheus peuvent mettre 1 a 2 minutes a stabiliser leurs etats apres injection ou restauration.

## 16. Procedures de diagnostic

### 16.1 Un conteneur est arrete ou unhealthy

```bash
docker compose ps <service>
docker compose logs --tail 100 <service>
docker compose restart <service>
```

Si le service a des sidecars :

```bash
docker compose up -d --force-recreate --no-deps <sidecar>
```

### 16.2 Zabbix affiche `Not available`

Causes frequentes :

- agent pas encore enregistre ;
- sidecar attache a un ancien namespace ;
- nom d'hote incorrect ;
- service cible arrete.

Diagnostic :

```bash
docker compose ps zabbix-agent-<hote>
docker compose exec -T artzab01p zabbix_get -s <hote> -k agent.ping
```

Correction :

```bash
docker compose up -d --force-recreate --no-deps zabbix-agent-<hote>
./zabbix/setup-hosts.sh
```

### 16.3 Nagios indique `Connection refused` sur un exporter

Cas typique :

```text
connect to address artweb01p and port 9113: Connection refused
```

Cause probable : exporter sidecar reste attache a l'ancien namespace reseau apres redemarrage de la machine simulee.

Correction :

```bash
docker compose up -d --force-recreate --no-deps nginx-exporter-artweb01p
docker compose up -d --force-recreate --no-deps postgres-exporter-artbdd02p
```

### 16.4 Prometheus target down

Diagnostic :

```bash
curl -fsS http://localhost:9090/-/healthy
```

Puis ouvrir :

```text
http://localhost:9090/targets
```

Corrections usuelles :

- verifier que le conteneur cible est `Up` ;
- verifier l'exporter associe ;
- relancer `./up.sh` pour recreer les sidecars ;
- verifier `prometheus/prometheus.yml` apres modification.

### 16.5 Graylog ne demarre pas

Diagnostics :

```bash
docker compose ps artgra01p artgraidx01p artgradb01p
docker compose logs --tail 100 artgra01p
docker compose logs --tail 100 artgraidx01p
cat /proc/sys/vm/max_map_count
```

Correction courante :

```bash
sudo sysctl -w vm.max_map_count=262144
docker compose restart artgraidx01p artgra01p
```

### 16.6 Nagios affiche d'anciens noms

Si des anciens noms comme `artgry01p`, `artgrydb01p`, `artgryidx01p`, `artprom01p` ou `artglp01p` reapparaissent, redemarrer Nagios et relancer le bootstrap Zabbix :

```bash
docker compose restart artnag01p
./zabbix/setup-hosts.sh
./zabbix/setup-dashboard.py
```

## 17. Maintenance de configuration

Apres modification de fichiers Compose, Dockerfile ou configuration service :

```bash
docker compose config --quiet
./up.sh --build
```

Apres modification uniquement des dashboards, checks ou scripts de bootstrap :

```bash
docker compose config --quiet
./up.sh
```

Fichiers principaux :

| Fichier | Role |
|---|---|
| `docker-compose.yml` | Definition de la stack |
| `up.sh` / `down.sh` | Cycle de vie du lab |
| `nagios/conf.d/artemis.cfg` | Checks Nagios Artemis |
| `prometheus/prometheus.yml` | Targets Prometheus |
| `grafana/provisioning/` | Datasource, dashboard, alertes |
| `zabbix/setup-hosts.sh` | Creation des hosts et items Zabbix |
| `zabbix/setup-dashboard.py` | Creation du dashboard Zabbix |
| `graylog/setup-inputs.sh` | Creation des inputs Graylog |
| `run-scenario.sh` | Scenarios de panne |

## 18. Validation de livraison

Avant demonstration ou remise :

```bash
docker compose config --quiet
./up.sh
docker compose ps
curl -fsS http://localhost
curl -fsS http://localhost:9090/-/healthy
curl -fsS http://localhost:9000/api/system/lbstatus
docker compose exec -T artzab01p zabbix_get -s artweb01p -k agent.ping
docker compose exec -T artnag01p nagios -v /opt/nagios/etc/nagios.cfg
```

Points a verifier dans les interfaces :

- HAProxy stats : `artweb01p` et `artweb02p` sont `UP` ;
- Nagios : les services principaux sont `OK` ;
- Zabbix : les hosts Artemis ont l'agent disponible ;
- Prometheus : les targets critiques sont `UP` ;
- Grafana : dashboard `Artemis Supervision` alimente ;
- Graylog/Splunk : les logs de test arrivent ;
- GLPI : l'interface repond sur `localhost:8082`.

## 19. Limites assumees

| Sujet | Decision |
|---|---|
| Deuxieme HAProxy / VIP | Non simule, un seul HAProxy suffit pour la demonstration |
| VLAN / segmentation reseau | Non simule dans Docker Compose |
| SMTP | Non simule, pas de notification mail |
| Annuaire / LDAP | Non simule |
| Durcissement securite | Hors perimetre du projet |
| Sauvegarde production | Remplacee par une preuve technique supervisee |
| Secrets | Identifiants par defaut locaux uniquement |

## 20. Documents associes

| Document | Usage |
|---|---|
| `README.md` | Presentation rapide du lab |
| `PROCEDURE.md` | Procedure detaillee de demarrage et usage |
| `SCHEMA_FLUX.md` | Schemas des flux entre conteneurs |
| `SUPERVISION_THRESHOLDS.md` | Contrat de supervision et seuils |
| `NOMMAGE_ET_CHOIX_OUTILS.md` | Nommage canonique et choix de cadrage |
| `SCENARIOS_DE_PANNE.md` | Deroule des scenarios de panne |
| `SUIVI_TRAVAUX.md` | Suivi des travaux realises |
