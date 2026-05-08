# Artemis Supervision Thresholds

This document defines what the lab should measure and when each signal becomes `WARNING` or `CRITICAL`, using the same operational logic as Nagios.

## Scope

The RAO architecture includes a frontend HAProxy layer, backend web servers, SFTP/NFS file-transfer services, SMTP, LDAP, clustered databases, and SIEM/supervision tools. The current lab implements HAProxy, two Nginx backends, SFTP, NFS, Zabbix, Nagios, Prometheus, Grafana, and Blackbox Exporter.

## Global Host Health

| Metric | Applies to | Warning | Critical | Tool |
|---|---|---:|---:|---|
| Host availability / ping | All hosts | packet loss > 20% or latency > 100 ms | packet loss > 60% or latency > 500 ms | Nagios, Blackbox |
| CPU utilization | Linux hosts | > 80% for 5 min | > 90% for 5 min | Zabbix |
| Memory utilization | Linux hosts | > 80% for 5 min | > 90% for 5 min | Zabbix |
| Disk usage | Linux hosts, data volumes | > 80% | > 90% | Zabbix |
| Filesystem read-only or unavailable | Web/SFTP/NFS data paths | any detection | path unavailable | Zabbix/Nagios |

## Frontend: HAProxy

| Metric | Warning | Critical | Notes |
|---|---:|---:|---|
| `http_front` status | n/a | not `UP` for 1 min | Main user entry point |
| Backend server status | one backend down | all backends down | Check `artweb01p` and `artweb02p` |
| HTTP 5xx rate | > 0 req/s for 2 min | > 1 req/s for 2 min | Indicates frontend/backend failure |
| HTTP 4xx rate | > 5 req/s for 5 min | > 20 req/s for 5 min | Possible client or routing issue |
| Active sessions | > 70% max sessions | > 90% max sessions | Capacity planning |
| Response time | > 500 ms | > 2 s | Measure from Blackbox HTTP probes |

## Backend Web

| Metric | Warning | Critical | Notes |
|---|---:|---:|---|
| HTTP availability | one failed probe | failed for 1 min | Blackbox HTTP and Nagios `check_http` |
| Nginx status endpoint | unavailable | unavailable for 1 min | `/nginx_status` |
| Request rate imbalance | one backend < 30% of traffic | one backend gets 0 traffic while UP | Detect load-balancing issues |
| Active Nginx connections | > 100 | > 500 | Lab-scale thresholds |

## File Services: SFTP and NFS

| Metric | Warning | Critical | Notes |
|---|---:|---:|---|
| SFTP TCP port 22 | failed once | failed for 1 min | `artsft02p:22` |
| NFS TCP port 2049 | failed once | failed for 1 min | `artnfs01p:2049` |
| Backup freshness | no run in 30 min | no run in 60 min | For future `transfert-web` and `copy-web` scripts |
| Backup result | last run failed | two consecutive failures | Track once backup scripts are implemented |
| Backup storage usage | > 80% | > 90% | Applies to SFTP/NFS volumes |

## SIEM and Monitoring

| Metric | Warning | Critical | Notes |
|---|---:|---:|---|
| Prometheus scrape target `up` | any target down for 1 min | key target down for 5 min | Current Grafana alert covers this |
| Grafana availability | failed probe | failed for 1 min | UI and alert visibility |
| Zabbix server process | unavailable | unavailable for 1 min | Monitoring continuity |
| Nagios UI availability | failed probe | failed for 1 min | Operational checks |

## Current Grafana Alert

Grafana currently provisions one consolidated rule, `Artemis lab health problem`. It triggers when HAProxy frontend is down, a backend is down in HAProxy, any Prometheus scrape target is down, an HTTP/SFTP/NFS Blackbox probe fails, or HAProxy returns frontend 5xx responses. Split this into separate rules later if Grafana provisioning state is reset or migrated away from the current SQLite lab volume.
