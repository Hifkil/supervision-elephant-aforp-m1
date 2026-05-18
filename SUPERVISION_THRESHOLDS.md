# Artemis Supervision Thresholds

This file is the monitoring contract for the lab: it states what is watched, why it matters, and when the state becomes `WARNING` or `CRITICAL`.

## Scope and Mapping

The lab intentionally keeps a reduced, reproducible Artemis architecture: one HAProxy frontend, two Nginx web backends, one PostgreSQL primary/replica pair, SFTP/NFS file services, a simple backup job, and the monitoring stack. SMTP, LDAP/annuaire, VIP HAProxy and network zoning are out of scope by design. Graylog, Rsyslog or Splunk can be added later if the comparison needs a log/SIEM angle. In Docker, each container represents one Artemis machine; `artmet01p` exports the system metrics that would normally come from VM agents.

## Platform and Container Health

| Metric | Applies to | Warning | Critical | Source |
|---|---|---:|---:|---|
| Container availability | All lab containers | missing scrape for 1 min | container stopped or missing for 5 min | Prometheus `up`, `artmet01p` |
| CPU usage | All Artemis containers | > 80% for 5 min | > 90% for 5 min | `artemis_container_cpu_percent` |
| Memory usage | All Artemis containers | > 80% for 5 min | > 90% for 5 min | `artemis_container_memory_percent` |
| Block I/O | All Artemis containers | unusual sustained spike | service impact or saturation | `artmet01p` |
| Network throughput anomaly | HAProxy, web, SFTP/NFS | sudden sustained spike | service impact or packet loss | `artmet01p`, Blackbox |
| Restart loop | All containers | > 1 restart in 10 min | repeated restarts for 15 min | Docker/cAdvisor |

## Frontend: HAProxy

| Metric | Warning | Critical | Source |
|---|---:|---:|---|
| `http_front` status | n/a | not `UP` for 1 min | HAProxy exporter |
| Backend server status | one backend down | all backends down | HAProxy exporter |
| Frontend HTTP probe | latency > 500 ms | probe fails or latency > 2 s | Blackbox |
| HTTP 5xx rate | > 0 req/s for 2 min | > 1 req/s for 2 min | HAProxy exporter |
| HTTP 4xx rate | > 5 req/s for 5 min | > 20 req/s for 5 min | HAProxy exporter |
| Active sessions | > 70% max sessions | > 90% max sessions | HAProxy exporter |

## Web Backends

| Metric | Warning | Critical | Source |
|---|---:|---:|---|
| HTTP availability | one failed probe | failed for 1 min | Blackbox, Nagios |
| ICMP availability | packet loss > 20% or > 100 ms | packet loss > 60% or > 500 ms | Blackbox, Nagios |
| Nginx status endpoint | unavailable once | unavailable for 1 min | Nginx exporter, Nagios |
| Request distribution | one backend < 30% traffic while both UP | one backend receives 0 traffic while UP | HAProxy exporter |
| Active Nginx connections | > 100 | > 500 | Nginx exporter |

## File Services and Backup

| Metric | Warning | Critical | Source |
|---|---:|---:|---|
| SFTP TCP port 22 | failed once | failed for 1 min | Blackbox, Nagios |
| NFS TCP port 2049 | failed once | failed for 1 min | Blackbox, Nagios |
| Backup job status | last run failed | two consecutive failed runs | `artbkp01p` metrics |
| Backup freshness | no success in 30 min | no success in 60 min | `artemis_backup_last_success_timestamp_seconds` |
| Copied file count | lower than expected | zero files copied | `artemis_backup_copied_files` |
| Backup storage usage | > 80% | > 90% | `artemis_volume_filesystem_used_percent` |

## Database Cluster

| Metric | Warning | Critical | Source |
|---|---:|---:|---|
| PostgreSQL primary TCP | failed once | failed for 1 min | Blackbox TCP, Nagios, Zabbix simple check |
| PostgreSQL replica TCP | failed once | failed for 1 min | Blackbox TCP, Nagios, Zabbix simple check |
| PostgreSQL exporter scrape | missing once | missing for 5 min | Prometheus `up`, `pg_up`, Nagios exporter check |
| Database activity | unusual sustained drop or spike | service impact | `pg_stat_database_*` |
| PostgreSQL volume usage | > 80% | > 90% | `artemis_volume_filesystem_used_percent` |

## Monitoring Stack

| Metric | Warning | Critical | Source |
|---|---:|---:|---|
| Prometheus scrape target `up` | any target down for 1 min | key target down for 5 min | Prometheus |
| Grafana UI | TCP probe fails once | unavailable for 1 min | Blackbox, Docker healthcheck |
| Zabbix web/server | TCP or process check fails | unavailable for 1 min | Docker healthcheck, Zabbix simple check, Nagios |
| Nagios UI | TCP probe fails once | unavailable for 1 min | Blackbox, Docker healthcheck, Zabbix simple check |
| Docker metrics scrape | missing once | missing for 5 min | Prometheus |

## Disk and Volume Capacity

| Metric | Warning | Critical | Source |
|---|---:|---:|---|
| Volume filesystem usage | > 80% for 5 min | > 90% for 5 min | `artemis_volume_filesystem_used_percent` |
| Volume apparent data size | rapid sustained growth | unexpected exhaustion risk | `artemis_volume_used_bytes` |

## Grafana Alerts

Grafana provisions separate rules by domain: frontend, web backends, file services, database, backup, platform resources and monitoring stack. Notification routing is intentionally not configured for this lab.
