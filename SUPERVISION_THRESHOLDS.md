# Seuils de supervision Artemis

Version : 1.0  
Date de verification : 2026-05-21  
Perimetre : maquette Docker Compose `supervision-elephant-aforp-m1`

Ce document est le contrat de supervision de la maquette Artemis. Il indique ce qui est surveille, avec quelle source technique, et a partir de quel seuil l'etat doit etre considere `WARNING` ou `CRITICAL`.

## 1. Perimetre retenu

La maquette simule une infrastructure Artemis reduite mais exploitable :

- un frontal HAProxy `arthpx01p` ;
- deux backends web Nginx `artweb01p` et `artweb02p` ;
- un cluster PostgreSQL primaire/replique `artbdd01p` / `artbdd02p` ;
- GLPI `artglpt01p` avec base MySQL dediee `artglptdb01p` ;
- services fichiers `artsft02p`, `artnfs01p` et preuve de sauvegarde `artbkp01p` ;
- supervision Zabbix, Nagios, Prometheus et Grafana ;
- chaine logs/SIEM Rsyslog, Graylog et Splunk.

Sont volontairement hors perimetre : deuxieme HAProxy, VIP, VLAN, SMTP, annuaire/LDAP, notifications mail et durcissement securite. Ces choix sont documentes dans `NOMMAGE_ET_CHOIX_OUTILS.md`.

## 2. Sources de supervision

| Source | Role | Donnees utilisees |
|---|---|---|
| Zabbix | Supervision infra et checks simples | Agents `zabbix-agent-*`, templates Linux/Nginx/HAProxy, items `net.tcp.service[...]` et `net.tcp.service.perf[...]` |
| Nagios | Etats actifs lisibles | `check_http`, `check_tcp`, `check_icmp`, contenu HTTP, roles PostgreSQL et exporters |
| Prometheus | Metriques numeriques | Jobs `prometheus`, `docker_metrics`, `artemis_backup`, `nginx`, `postgres`, `blackbox_*`, `haproxy` |
| Grafana | Visualisation et alertes | Dashboard `Artemis Supervision` et regles provisionnees dans `grafana/provisioning/alerting/artemis-alerts.yml` |
| Blackbox Exporter | Tests externes | `probe_success`, `probe_duration_seconds` pour HTTP, TCP et ICMP |
| `artmet01p` | Metriques Docker | CPU, RAM, etat conteneur, redemarrages, reseau, I/O disque et volumes |
| `artbkp01p` | Metriques backup | Statut, fraicheur, duree et nombre de fichiers copies |

## 3. Metriques verifiees

Les metriques ci-dessous ont ete verifiees sur Prometheus via `/api/v1/query` le 2026-05-21.

| Domaine | Metriques disponibles |
|---|---|
| Prometheus / scrape | `up` |
| Blackbox | `probe_success`, `probe_duration_seconds` |
| HAProxy | `haproxy_frontend_status`, `haproxy_server_status`, `haproxy_frontend_http_responses_total`, `haproxy_server_http_responses_total`, `haproxy_frontend_current_sessions` |
| Nginx | `nginx_up`, `nginx_connections_active`, `nginx_http_requests_total` |
| PostgreSQL | `pg_up`, `pg_replication_is_replica`, `pg_replication_lag_seconds`, `pg_stat_replication_pg_wal_lsn_diff`, `pg_stat_database_xact_commit`, `pg_stat_database_xact_rollback` |
| Backup | `artemis_backup_last_status`, `artemis_backup_last_success_timestamp_seconds`, `artemis_backup_last_duration_seconds`, `artemis_backup_copied_files`, `artemis_backup_loop_interval_seconds` |
| Conteneurs Docker | `artemis_container_running`, `artemis_container_cpu_percent`, `artemis_container_memory_percent`, `artemis_container_network_receive_bytes_total`, `artemis_container_network_transmit_bytes_total`, `artemis_container_block_read_bytes_total`, `artemis_container_block_write_bytes_total`, `artemis_container_restart_count` |
| Volumes Docker | `artemis_volume_used_bytes`, `artemis_volume_filesystem_size_bytes`, `artemis_volume_filesystem_available_bytes`, `artemis_volume_filesystem_used_percent` |
| Exporter Docker | `artemis_docker_metrics_last_scrape_timestamp_seconds` |

Toutes les expressions d'alerte Grafana provisionnees ont egalement ete testees contre Prometheus et retournent un resultat valide.

## 4. Capacite plateforme et conteneurs

| Controle | Metrique / source | WARNING | CRITICAL | Remarque |
|---|---|---:|---:|---|
| Conteneur arrete | `artemis_container_running{service="..."}` | `0` pendant 1 min | `0` pendant 5 min | Metrique exposee par `artmet01p` |
| CPU conteneur | `artemis_container_cpu_percent` | `> 80%` pendant 5 min | `> 90%` pendant 5 min | Alerte Grafana sur `> 90%` |
| RAM conteneur | `artemis_container_memory_percent` | `> 80%` pendant 5 min | `> 90%` pendant 5 min | Alerte Grafana sur `> 90%` |
| Redemarrages | `artemis_container_restart_count` | augmentation `> 1` en 10 min | augmentation repetee sur 15 min | La source est `artmet01p`, pas cAdvisor |
| Trafic reseau | `rate(artemis_container_network_receive_bytes_total[5m])` et `rate(artemis_container_network_transmit_bytes_total[5m])` | hausse durable anormale | impact service ou perte de connectivite | Metrique de tendance, pas d'alerte Grafana dediee |
| I/O disque conteneur | `rate(artemis_container_block_read_bytes_total[5m])` et `rate(artemis_container_block_write_bytes_total[5m])` | hausse durable anormale | saturation ou impact service | Metrique de tendance, pas d'alerte Grafana dediee |
| Occupation volumes | `artemis_volume_filesystem_used_percent` | `> 80%` pendant 5 min | `> 90%` pendant 5 min | Alerte Grafana sur `> 90%` |
| Taille apparente volumes | `artemis_volume_used_bytes` | croissance rapide | risque d'epuisement disque | Metrique de tendance |

Expression Grafana active :

```promql
max((artemis_container_cpu_percent > bool 90) or (artemis_container_memory_percent > bool 90) or (artemis_volume_filesystem_used_percent > bool 90) or vector(0))
```

## 5. Frontend HAProxy

| Controle | Metrique / source | WARNING | CRITICAL | Remarque |
|---|---|---:|---:|---|
| Frontend HTTP UP | `haproxy_frontend_status{proxy="http_front",state="UP"}` | n/a | different de `1` pendant 1 min | Alerte Grafana active |
| Backend disponible | `haproxy_server_status{proxy="nginx_backends",state="UP"}` | un backend down | tous les backends down | Alerte Grafana active des qu'un backend est down |
| Reponses HTTP 5xx | `rate(haproxy_frontend_http_responses_total{proxy="http_front",code="5xx"}[2m])` | `> 0` pendant 2 min | `> 1 req/s` pendant 2 min | Alerte Grafana active des qu'un taux non nul apparait |
| Reponses HTTP 4xx | `rate(haproxy_frontend_http_responses_total{proxy="http_front",code="4xx"}[5m])` | `> 5 req/s` pendant 5 min | `> 20 req/s` pendant 5 min | Dashboard, pas d'alerte dediee |
| Sessions actives | `haproxy_frontend_current_sessions{proxy="http_front"}` | tendance anormale | saturation visible | Seuil de tendance, pas de limite max explicite dans la maquette |
| Probe HTTP frontal | `probe_success{job="blackbox_http",instance="http://arthpx01p"}` | `0` sur 1 scrape | `0` pendant 1 min | Verifie le service rendu |

Expression Grafana active :

```promql
max((1 - max(haproxy_frontend_status{proxy="http_front",state="UP"})) or clamp_max(sum(rate(haproxy_frontend_http_responses_total{proxy="http_front",code="5xx"}[2m])) * 1000, 1) or vector(0))
```

## 6. Backends web Nginx

| Controle | Metrique / source | WARNING | CRITICAL | Remarque |
|---|---|---:|---:|---|
| HTTP backend | `probe_success{job="blackbox_http",instance=~"http://artweb0[12]p"}` | un echec ponctuel | `0` pendant 1 min | Alerte Grafana active |
| Ping backend | `probe_success{job="blackbox_ping",instance=~"artweb0[12]p"}` | perte ponctuelle | `0` pendant 1 min | Alerte Grafana active |
| Latence HTTP | `probe_duration_seconds{job="blackbox_http",instance=~"http://artweb0[12]p"}` | `> 0.5 s` | `> 2 s` | Dashboard, pas d'alerte dediee |
| Nginx exporter | `nginx_up{instance=~"artweb0[12]p:9113"}` | `0` sur 1 scrape | `0` pendant 1 min | Check Nagios `Nginx Exporter Metrics` |
| Connexions actives | `nginx_connections_active` | `> 100` | `> 500` | Metrique disponible, seuil de maquette |
| Requetes Nginx | `rate(nginx_http_requests_total[1m])` | repartition desequilibree | backend UP sans requete durablement | A comparer avec HAProxy |
| Repartition HAProxy | `rate(haproxy_server_http_responses_total{proxy="nginx_backends"}[1m])` | un backend < 30% du trafic si les deux sont UP | un backend a 0% du trafic si les deux sont UP | Dashboard, pas d'alerte dediee |

Expression Grafana active :

```promql
max((1 - min(haproxy_server_status{proxy="nginx_backends",state="UP"})) or (1 - min(probe_success{job="blackbox_http",instance=~"http://artweb0[12]p"})) or (1 - min(probe_success{job="blackbox_ping",instance=~"artweb0[12]p"})) or vector(0))
```

## 7. Services fichiers et sauvegarde

| Controle | Metrique / source | WARNING | CRITICAL | Remarque |
|---|---|---:|---:|---|
| SFTP TCP | `probe_success{job="blackbox_tcp",instance="artsft02p:22"}` | `0` sur 1 scrape | `0` pendant 1 min | Alerte Grafana severity `warning` |
| NFS TCP | `probe_success{job="blackbox_tcp",instance="artnfs01p:2049"}` | `0` sur 1 scrape | `0` pendant 1 min | Alerte Grafana severity `warning` |
| Backup endpoint | `probe_success{job="blackbox_tcp",instance="artbkp01p:8080"}` | `0` sur 1 scrape | `0` pendant 1 min | Supervise l'endpoint metriques |
| Statut backup | `artemis_backup_last_status` | `1` sur le dernier run | `1` persistant | `0` = succes, `1` = echec |
| Fraicheur backup | `time() - artemis_backup_last_success_timestamp_seconds` | `> 1800 s` | `> 3600 s` | Alerte Grafana active sur `> 3600 s` |
| Duree backup | `artemis_backup_last_duration_seconds` | hausse inhabituelle | impact sur la frequence de run | Tendance |
| Fichiers copies | `artemis_backup_copied_files` | inferieur a l'attendu | `0` | Attendu actuel : au moins `1` |
| Occupation stockage | `artemis_volume_filesystem_used_percent{volume=~"nfs-web|sftp-ssh-keys"}` | `> 80%` | `> 90%` | Via `artmet01p` |

Expressions Grafana actives :

```promql
max((1 - min(probe_success{job="blackbox_tcp",instance=~"artsft02p:22|artnfs01p:2049"})) or vector(0))
max(artemis_backup_last_status or ((time() - artemis_backup_last_success_timestamp_seconds) > bool 3600) or vector(0))
```

## 8. GLPI

| Controle | Metrique / source | WARNING | CRITICAL | Remarque |
|---|---|---:|---:|---|
| GLPI HTTP | `probe_success{job="blackbox_http",instance="http://artglpt01p"}` | echec ponctuel | `0` pendant 1 min | Alerte Grafana active |
| GLPI latence HTTP | `probe_duration_seconds{job="blackbox_http",instance="http://artglpt01p"}` | `> 0.5 s` | `> 2 s` | Dashboard |
| Port GLPI HTTP | Zabbix `net.tcp.service[http,,80]` sur `artglpt01p` | `0` | `0` pendant 1 min | Item Zabbix simple |
| Latence GLPI Zabbix | Zabbix `net.tcp.service.perf[http,,80]` | `> 0.5 s` | `> 2 s` | Dashboard Zabbix |
| MySQL GLPI | `probe_success{job="blackbox_tcp",instance="artglptdb01p:3306"}` | echec ponctuel | `0` pendant 1 min | Alerte Grafana active |
| Port MySQL Zabbix | Zabbix `net.tcp.service[tcp,,3306]` sur `artglptdb01p` | `0` | `0` pendant 1 min | Item Zabbix simple |
| Volumes GLPI | `artemis_volume_filesystem_used_percent{volume=~"glpi-data|glpi-db"}` | `> 80%` | `> 90%` | Via `artmet01p` |

Expression Grafana active :

```promql
max((1 - min(probe_success{job="blackbox_http",instance="http://artglpt01p"})) or (1 - min(probe_success{job="blackbox_tcp",instance="artglptdb01p:3306"})) or vector(0))
```

## 9. Logs / SIEM

| Controle | Metrique / source | WARNING | CRITICAL | Remarque |
|---|---|---:|---:|---|
| Rsyslog TCP | `probe_success{job="blackbox_tcp",instance="artrsy01p:514"}` | echec ponctuel | `0` pendant 1 min | Alerte Grafana active |
| Graylog API | `probe_success{job="blackbox_http",instance="http://artgra01p:9000/api/system/lbstatus"}` | echec ponctuel | `0` pendant 1 min | Verifie `ALIVE` via HTTP |
| Graylog port HTTP | `probe_success{job="blackbox_tcp",instance="artgra01p:9000"}` | echec ponctuel | `0` pendant 1 min | Port web/API |
| Graylog Syslog | `probe_success{job="blackbox_tcp",instance="artgra01p:1514"}` | echec ponctuel | `0` pendant 1 min | Input Syslog TCP |
| MongoDB Graylog | `probe_success{job="blackbox_tcp",instance="artgradb01p:27017"}` | echec ponctuel | `0` pendant 1 min | Dependence Graylog |
| OpenSearch Graylog | `probe_success{job="blackbox_tcp",instance="artgraidx01p:9200"}` | echec ponctuel | `0` pendant 1 min | Dependence Graylog |
| Splunk Web | `probe_success{job="blackbox_http",instance="http://artspl01p:8000/en-US/account/login"}` | echec ponctuel | `0` pendant 1 min | Interface Splunk |
| Splunk HEC | `probe_success{job="blackbox_tcp",instance="artspl01p:8088"}` | echec ponctuel | `0` pendant 1 min | Ingestion HEC |
| Splunk Syslog | `probe_success{job="blackbox_tcp",instance="artspl01p:1515"}` | echec ponctuel | `0` pendant 1 min | Input syslog |
| Volumes SIEM | `artemis_volume_filesystem_used_percent{volume=~"graylog.*|splunk-data|rsyslog-spool"}` | `> 80%` | `> 90%` | Via `artmet01p` |

Expression Grafana active :

```promql
max((1 - min(probe_success{job="blackbox_tcp",instance=~"artgradb01p:27017|artgraidx01p:9200|artgra01p:9000|artgra01p:1514|artspl01p:8000|artspl01p:8088|artspl01p:1515|artrsy01p:514"})) or (1 - min(probe_success{job="blackbox_http",instance=~"http://artgra01p:9000/api/system/lbstatus|http://artspl01p:8000/en-US/account/login"})) or vector(0))
```

## 10. Cluster PostgreSQL Artemis

| Controle | Metrique / source | WARNING | CRITICAL | Remarque |
|---|---|---:|---:|---|
| Port primaire | `probe_success{job="blackbox_tcp",instance="artbdd01p:5432"}` | echec ponctuel | `0` pendant 1 min | Alerte Grafana active |
| Port replique | `probe_success{job="blackbox_tcp",instance="artbdd02p:5432"}` | echec ponctuel | `0` pendant 1 min | Alerte Grafana active |
| Exporter PostgreSQL | `up{job="postgres"}` | scrape manquant | `0` pendant 1 min | Alerte Grafana active |
| PostgreSQL up | `pg_up{job="postgres"}` | `0` sur un noeud | `0` pendant 1 min | Alerte Grafana active |
| Role primaire | `pg_replication_is_replica{instance="artbdd01p:9187"}` | different de `0` | different de `0` pendant 1 min | Check Nagios `PostgreSQL Primary Role` |
| Role replique | `pg_replication_is_replica{instance="artbdd02p:9187"}` | different de `1` | different de `1` pendant 1 min | Check Nagios `PostgreSQL Replica Role` |
| Lag replique | `pg_replication_lag_seconds{instance="artbdd02p:9187"}` | `> 30 s` | `> 120 s` | Metrique disponible |
| Flux replication | `pg_stat_replication_pg_wal_lsn_diff` | absent cote primaire | absent ou en hausse durable | Present sur le primaire uniquement |
| Activite base | `rate(pg_stat_database_xact_commit[5m])`, `rate(pg_stat_database_xact_rollback[5m])` | variation inhabituelle | impact applicatif | Tendance |
| Volumes PostgreSQL | `artemis_volume_filesystem_used_percent{volume=~"artbdd0[12]p-data"}` | `> 80%` | `> 90%` | Via `artmet01p` |

Expression Grafana active :

```promql
max((1 - min(probe_success{job="blackbox_tcp",instance=~"artbdd0[12]p:5432"})) or (1 - min(up{job="postgres"})) or (1 - min(pg_up{job="postgres"})) or vector(0))
```

## 11. Pile de supervision

| Controle | Metrique / source | WARNING | CRITICAL | Remarque |
|---|---|---:|---:|---|
| Prometheus scrape | `up{job=...}` | une target non critique down pendant 1 min | target critique down pendant 5 min | Vue principale dans Prometheus |
| Prometheus UI | `probe_success{job="blackbox_tcp",instance="artpgr01p:9090"}` | echec ponctuel | `0` pendant 1 min | Alerte Grafana active |
| Docker metrics | `up{job="docker_metrics"}` | scrape manquant | `0` pendant 1 min | Alerte Grafana active |
| Exporter Docker recent | `time() - artemis_docker_metrics_last_scrape_timestamp_seconds` | `> 60 s` | `> 300 s` | Metrique disponible |
| Grafana UI | `probe_success{job="blackbox_tcp",instance="artgrf01p:3000"}` | echec ponctuel | `0` pendant 1 min | Alerte Grafana active |
| Zabbix Web | `probe_success{job="blackbox_tcp",instance="artzabweb01p:8080"}` | echec ponctuel | `0` pendant 1 min | Alerte Grafana active |
| Zabbix Server | Zabbix/Nagios `artzab01p:10051` | echec ponctuel | port indisponible pendant 1 min | Check Nagios et item Zabbix |
| Nagios Web | `probe_success{job="blackbox_tcp",instance="artnag01p:80"}` | echec ponctuel | `0` pendant 1 min | Alerte Grafana active |
| Blackbox Exporter | Zabbix/Nagios `artbbx01p:9115` | echec ponctuel | port indisponible pendant 1 min | Check Nagios et item Zabbix |

Expression Grafana active :

```promql
max((1 - min(probe_success{job="blackbox_tcp",instance=~"artzabweb01p:8080|artnag01p:80|artpgr01p:9090|artgrf01p:3000"})) or (1 - min(up{job=~"prometheus|docker_metrics"})) or vector(0))
```

## 12. Correspondance Nagios

Nagios verifie 24 hotes et 72 services. Les checks principaux utilises dans ce contrat sont :

| Domaine | Checks Nagios |
|---|---|
| Web | `PING`, `HTTP`, `HTTP Content`, `Nginx Status`, `Nginx Exporter Metrics` |
| HAProxy | `HTTP via HAProxy`, `HAProxy Stats`, `HAProxy Prometheus Metrics`, `HAProxy Zabbix CSV` |
| Fichiers | `SFTP TCP`, `NFS TCP` |
| PostgreSQL | `PostgreSQL TCP`, `PostgreSQL Exporter pg_up`, `PostgreSQL Primary Role`, `PostgreSQL Replica Role`, `PostgreSQL Replica Lag Metric` |
| GLPI | `GLPI HTTP`, `GLPI HTTP Content`, `GLPI MySQL TCP` |
| SIEM/logs | `Graylog API Health`, `Graylog Syslog TCP`, `OpenSearch HTTP`, `Splunk Web`, `Splunk HEC TCP`, `Splunk Syslog TCP`, `Rsyslog TCP` |
| Backup | `Backup Metrics HTTP`, `Backup File Count Metric` |
| Supervision | `Zabbix Server TCP`, `Zabbix Web Ping`, `Blackbox Exporter Metrics`, `Docker Metrics Exporter`, `Prometheus Healthy`, `Grafana API Health`, `Nagios Web UI` |

## 13. Correspondance Zabbix

Les items applicatifs ajoutes par `zabbix/setup-hosts.sh` sont des checks simples de type Zabbix :

- `net.tcp.service[tcp,,<port>]` pour les ports TCP ;
- `net.tcp.service[http,,<port>]` pour les endpoints HTTP ;
- `net.tcp.service[ssh,,22]` pour SFTP ;
- `net.tcp.service.perf[...]` pour les temps de reponse.

Les templates natifs restent actifs :

- `Linux by Zabbix agent` pour les metriques systeme ;
- `Nginx by Zabbix agent` pour `artweb01p` et `artweb02p` ;
- `HAProxy by HTTP` pour `arthpx01p`.

## 14. Regles Grafana provisionnees

| Regle | Severite | Declenchement |
|---|---|---|
| `Artemis frontend HAProxy problem` | `critical` | HAProxy frontal down ou 5xx |
| `Artemis web backend problem` | `critical` | backend HAProxy, HTTP ou ping backend down |
| `Artemis GLPI problem` | `critical` | GLPI HTTP ou MySQL down |
| `Artemis SIEM/logs problem` | `critical` | un composant SIEM/logs ou port d'ingestion down |
| `Artemis file service problem` | `warning` | SFTP ou NFS down |
| `Artemis PostgreSQL cluster problem` | `critical` | PostgreSQL TCP, exporter ou `pg_up` down |
| `Artemis backup problem` | `warning` | dernier backup en echec ou aucun succes depuis 1 h |
| `Artemis platform capacity problem` | `warning` | CPU, RAM ou volume > 90% pendant 5 min |
| `Artemis monitoring stack problem` | `critical` | interface de supervision ou scrape critique down |

Le routage de notification n'est volontairement pas configure dans cette maquette.
