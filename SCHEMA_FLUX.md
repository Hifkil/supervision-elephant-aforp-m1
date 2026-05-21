# Schema des flux entre conteneurs Artemis

Ce document decrit les flux reseau et les dependances principales de la maquette Docker Compose Artemis. Les volumes Docker et montages locaux sont separes des flux reseau, car ils ne passent pas par le reseau `artemis`.

Code couleur utilise dans les schemas :

| Couleur | Domaine |
|---|---|
| Orange | Acces depuis l'hote Docker / navigateur |
| Bleu | Frontend web et services applicatifs |
| Vert | Bases de donnees |
| Jaune | ITSM ou exporters |
| Cyan | Services fichiers et sauvegarde |
| Violet | Logs / SIEM |
| Rouge | Zabbix et supervision active |
| Indigo | Prometheus / Grafana |
| Gris | Stockage, montages et sidecars techniques |

## 1. Vue globale concise pour slide

Cette version tient sur une slide : les conteneurs sont regroupes par domaine et seuls les flux essentiels sont affiches.

Export PNG 16:9 : [Livrables/Vue Globale Slide 16-9.png](Livrables/Vue%20Globale%20Slide%2016-9.png).

```mermaid
flowchart LR
  USER[Utilisateurs<br/>navigateur / SFTP / logs]

  subgraph APP["Services applicatifs"]
    HPX[HAProxy<br/>arthpx01p]
    WEB[Web Nginx<br/>artweb01p / artweb02p]
    GLPI[GLPI<br/>artglpt01p]
    BDD[Bases de donnees<br/>PostgreSQL primaire/replique<br/>+ MySQL GLPI]
    FILES[SFTP / NFS / Backup<br/>artsft02p / artnfs01p / artbkp01p]
  end

  subgraph LOGS["Logs / SIEM"]
    RSY[Rsyslog<br/>artrsy01p]
    SIEM[Graylog + Splunk<br/>artgra01p / artspl01p]
    INDEX[MongoDB + OpenSearch<br/>artgradb01p / artgraidx01p]
  end

  subgraph MON["Supervision"]
    ZBX[Zabbix<br/>artzab01p / artzabweb01p]
    NAG[Nagios<br/>artnag01p]
    PROM[Prometheus + Grafana<br/>artpgr01p / artgrf01p]
    PROBES[Blackbox + exporters<br/>artbbx01p / artmet01p]
  end

  USER -->|HTTP 80| HPX
  HPX -->|HTTP| WEB
  USER -->|HTTP 8082| GLPI
  GLPI -->|MySQL| BDD
  USER -->|SFTP 2222| FILES

  USER -->|Syslog 10514| RSY
  RSY -->|1514 / 1515| SIEM
  SIEM -->|stockage / index| INDEX

  ZBX -->|agents + checks TCP| APP
  NAG -->|checks actifs| APP
  PROM -->|scrape metrics| PROBES
  PROBES -->|probes HTTP/TCP/ICMP| APP
  PROM -->|datasource| MON

  classDef user fill:#fff7ed,stroke:#ea580c,color:#111827
  classDef app fill:#dbeafe,stroke:#2563eb,color:#111827
  classDef logs fill:#f3e8ff,stroke:#9333ea,color:#111827
  classDef mon fill:#e0e7ff,stroke:#4f46e5,color:#111827
  classDef db fill:#dcfce7,stroke:#16a34a,color:#111827
  classDef files fill:#e0f2fe,stroke:#0284c7,color:#111827

  class USER user
  class HPX,WEB,GLPI app
  class BDD db
  class FILES files
  class RSY,SIEM,INDEX logs
  class ZBX,NAG,PROM,PROBES mon
```

## 2. Flux applicatifs

```mermaid
flowchart LR
  EXT[Poste hote]

  HPX[arthpx01p<br/>HAProxy]
  WEB1[artweb01p<br/>Nginx backend 1]
  WEB2[artweb02p<br/>Nginx backend 2]

  GLPI[artglpt01p<br/>GLPI]
  GLPIDB[artglptdb01p<br/>MySQL]

  PG1[artbdd01p<br/>PostgreSQL primaire]
  PG2[artbdd02p<br/>PostgreSQL replique]

  SFTP[artsft02p<br/>SFTP]
  NFS[artnfs01p<br/>NFS]
  BKP[artbkp01p<br/>Backup demo]

  EXT -->|HTTP 80| HPX
  HPX -->|HTTP 80 / healthcheck| WEB1
  HPX -->|HTTP 80 / healthcheck| WEB2

  EXT -->|HTTP 8082 -> 80| GLPI
  GLPI -->|MySQL 3306| GLPIDB

  PG1 -->|streaming replication 5432| PG2

  EXT -->|SFTP 2222 -> 22| SFTP
  BKP -->|cp vers montage /backup/sftp| SFTP
  BKP -->|cp vers volume /backup/nfs| NFS

  classDef ext fill:#fff7ed,stroke:#ea580c,color:#111827
  classDef web fill:#dbeafe,stroke:#2563eb,color:#111827
  classDef db fill:#dcfce7,stroke:#16a34a,color:#111827
  classDef itsm fill:#fef3c7,stroke:#d97706,color:#111827
  classDef files fill:#e0f2fe,stroke:#0284c7,color:#111827

  class EXT ext
  class HPX,WEB1,WEB2 web
  class PG1,PG2 db
  class GLPI,GLPIDB itsm
  class SFTP,NFS,BKP files
```

| Source | Destination | Port / protocole | Rôle |
|---|---|---|---|
| Poste hote | `arthpx01p` | HTTP `80` | Entree web de la maquette |
| `arthpx01p` | `artweb01p` | HTTP `80` | Routage backend HAProxy |
| `arthpx01p` | `artweb02p` | HTTP `80` | Routage backend HAProxy |
| Poste hote | `artglpt01p` | HTTP `8082 -> 80` | Acces GLPI |
| `artglpt01p` | `artglptdb01p` | MySQL `3306` | Base de donnees GLPI |
| `artbdd01p` | `artbdd02p` | PostgreSQL `5432` | Replication primaire vers replique |
| Poste hote | `artsft02p` | SFTP `2222 -> 22` | Acces fichiers |
| `artbkp01p` | `artsft02p` | Montage `./sftp/web` | Copie sauvegarde vers SFTP |
| `artbkp01p` | `artnfs01p` | Volume `nfs-web` | Copie sauvegarde vers NFS |

## 3. Flux logs / SIEM

```mermaid
flowchart LR
  EXT[Poste hote]
  DOCKER[Logs JSON Docker<br/>/var/lib/docker/containers]
  RSY[artrsy01p<br/>Rsyslog]
  GRA[artgra01p<br/>Graylog]
  GRADB[artgradb01p<br/>MongoDB]
  GRAIDX[artgraidx01p<br/>OpenSearch]
  SPL[artspl01p<br/>Splunk]

  EXT -->|Syslog TCP/UDP 10514 -> 514| RSY
  DOCKER -->|montage lecture seule| RSY
  RSY -->|Syslog TCP 1514| GRA
  RSY -->|Syslog TCP 1515| SPL
  EXT -->|GELF TCP/UDP 12201| GRA
  EXT -->|Graylog UI/API 9000| GRA
  EXT -->|Splunk UI 8000| SPL
  EXT -->|Splunk HEC 8088| SPL
  GRA -->|MongoDB 27017| GRADB
  GRA -->|OpenSearch 9200| GRAIDX

  classDef ext fill:#fff7ed,stroke:#ea580c,color:#111827
  classDef siem fill:#f3e8ff,stroke:#9333ea,color:#111827
  classDef storage fill:#f1f5f9,stroke:#64748b,color:#111827

  class EXT ext
  class RSY,GRA,SPL siem
  class DOCKER,GRADB,GRAIDX storage
```

| Source | Destination | Port / protocole | Rôle |
|---|---|---|---|
| Poste hote | `artrsy01p` | Syslog TCP/UDP `10514 -> 514` | Injection de logs de test |
| `/var/lib/docker/containers` | `artrsy01p` | Montage lecture seule | Lecture des logs JSON Docker |
| `artrsy01p` | `artgra01p` | Syslog TCP `1514` | Transmission vers Graylog |
| `artrsy01p` | `artspl01p` | Syslog TCP `1515` | Transmission vers Splunk |
| Poste hote | `artgra01p` | GELF TCP/UDP `12201` | Entree GELF Graylog |
| Poste hote | `artgra01p` | HTTP `9000` | Interface/API Graylog |
| Poste hote | `artspl01p` | HTTP `8000` | Interface Splunk |
| Poste hote | `artspl01p` | HTTP `8088` | Splunk HEC |
| `artgra01p` | `artgradb01p` | MongoDB `27017` | Metadata Graylog |
| `artgra01p` | `artgraidx01p` | HTTP `9200` | Indexation OpenSearch |

## 4. Flux supervision

```mermaid
flowchart LR
  EXT[Poste hote / navigateur]

  subgraph ZABBIX["Zabbix"]
    ZBXWEB[artzabweb01p<br/>Zabbix Web]
    ZBX[artzab01p<br/>Zabbix Server]
    ZBXDB[artdb01p<br/>PostgreSQL Zabbix]
    AGENTS[zabbix-agent-*<br/>sidecars par machine]
  end

  subgraph METRICS["Prometheus / Grafana"]
    PGR[artpgr01p<br/>Prometheus]
    GRF[artgrf01p<br/>Grafana]
    BBX[artbbx01p<br/>Blackbox Exporter]
    MET[artmet01p<br/>Docker metrics]
    NGINXEXP[nginx-exporter-artweb01p/02p]
    PGEXP[postgres-exporter-artbdd01p/02p]
  end

  NAG[artnag01p<br/>Nagios]
  TARGETS[Services Artemis<br/>web, db, glpi, siem, fichiers]

  EXT -->|HTTP 8080| ZBXWEB
  EXT -->|HTTP 8081| NAG
  EXT -->|HTTP 9090| PGR
  EXT -->|HTTP 3000| GRF

  ZBXWEB -->|10051| ZBX
  ZBXWEB -->|5432| ZBXDB
  ZBX -->|5432| ZBXDB
  ZBX -->|10050| AGENTS
  ZBX -->|HTTP/TCP checks| TARGETS

  NAG -->|HTTP/TCP/ICMP checks| TARGETS
  NAG -->|metrics checks| NGINXEXP
  NAG -->|metrics checks| PGEXP

  GRF -->|HTTP API 9090| PGR
  PGR -->|/probe 9115| BBX
  BBX -->|HTTP/TCP/ICMP probes| TARGETS
  PGR -->|8080 /metrics| MET
  PGR -->|9113 /metrics| NGINXEXP
  PGR -->|9187 /metrics| PGEXP
  PGR -->|8405 /metrics| TARGETS

  classDef ext fill:#fff7ed,stroke:#ea580c,color:#111827
  classDef zabbix fill:#fee2e2,stroke:#dc2626,color:#111827
  classDef nagios fill:#ffedd5,stroke:#f97316,color:#111827
  classDef prom fill:#e0e7ff,stroke:#4f46e5,color:#111827
  classDef targets fill:#dbeafe,stroke:#2563eb,color:#111827

  class EXT ext
  class ZBXWEB,ZBX,ZBXDB,AGENTS zabbix
  class NAG nagios
  class PGR,GRF,BBX,MET,NGINXEXP,PGEXP prom
  class TARGETS targets
```

| Source | Destination | Port / protocole | Rôle |
|---|---|---|---|
| Poste hote | `artzabweb01p` | HTTP `8080` | Interface Zabbix |
| `artzabweb01p` | `artzab01p` | Zabbix `10051` | Dialogue web vers serveur Zabbix |
| `artzabweb01p` | `artdb01p` | PostgreSQL `5432` | Donnees UI Zabbix |
| `artzab01p` | `artdb01p` | PostgreSQL `5432` | Base serveur Zabbix |
| `artzab01p` | `zabbix-agent-*` | Agent `10050` | Collecte metriques systeme |
| `artzab01p` | services supervises | HTTP/TCP | Items applicatifs simples |
| Poste hote | `artnag01p` | HTTP `8081 -> 80` | Interface Nagios |
| `artnag01p` | services supervises | HTTP/TCP/ICMP | Checks actifs Nagios |
| Poste hote | `artpgr01p` | HTTP `9090` | Interface Prometheus |
| Poste hote | `artgrf01p` | HTTP `3000` | Interface Grafana |
| `artgrf01p` | `artpgr01p` | HTTP `9090` | Datasource Grafana |
| `artpgr01p` | `artbbx01p` | HTTP `9115 /probe` | Probes Blackbox |
| `artbbx01p` | services supervises | HTTP/TCP/ICMP | Verification externe des services |
| `artpgr01p` | `artmet01p` | HTTP `8080 /metrics` | Metriques Docker |
| `artpgr01p` | `artbkp01p` | HTTP `8080 /metrics` | Metriques backup |
| `artpgr01p` | `artweb01p` / `artweb02p` | HTTP `9113 /metrics` | Metriques Nginx via exporters sidecars |
| `artpgr01p` | `artbdd01p` / `artbdd02p` | HTTP `9187 /metrics` | Metriques PostgreSQL via exporters sidecars |
| `artpgr01p` | `arthpx01p` | HTTP `8405 /metrics` | Metriques HAProxy |

## 5. Sidecars Zabbix et exporters

Les sidecars ci-dessous utilisent `network_mode: service:<machine>`. Ils ne possedent donc pas leur propre adresse IP sur le reseau Compose : ils partagent la pile reseau de la machine cible.

```mermaid
flowchart LR
  ZBX[artzab01p<br/>Zabbix Server]
  PGR[artpgr01p<br/>Prometheus]
  NAG[artnag01p<br/>Nagios]

  subgraph WEB["Machines web"]
    WEB1[artweb01p]
    ZA_WEB1[zabbix-agent-artweb01p]
    NX1[nginx-exporter-artweb01p]
    WEB2[artweb02p]
    ZA_WEB2[zabbix-agent-artweb02p]
    NX2[nginx-exporter-artweb02p]
  end

  subgraph PG["Machines PostgreSQL"]
    PG1[artbdd01p]
    ZA_PG1[zabbix-agent-artbdd01p]
    PGE1[postgres-exporter-artbdd01p]
    PG2[artbdd02p]
    ZA_PG2[zabbix-agent-artbdd02p]
    PGE2[postgres-exporter-artbdd02p]
  end

  WEB1 -. partage namespace reseau .-> ZA_WEB1
  WEB1 -. partage namespace reseau .-> NX1
  WEB2 -. partage namespace reseau .-> ZA_WEB2
  WEB2 -. partage namespace reseau .-> NX2
  PG1 -. partage namespace reseau .-> ZA_PG1
  PG1 -. partage namespace reseau .-> PGE1
  PG2 -. partage namespace reseau .-> ZA_PG2
  PG2 -. partage namespace reseau .-> PGE2

  ZBX -->|10050| WEB1
  ZBX -->|10050| WEB2
  ZBX -->|10050| PG1
  ZBX -->|10050| PG2
  PGR -->|9113| WEB1
  PGR -->|9113| WEB2
  PGR -->|9187| PG1
  PGR -->|9187| PG2
  NAG -->|9113| WEB1
  NAG -->|9113| WEB2
  NAG -->|9187| PG1
  NAG -->|9187| PG2

  classDef zabbix fill:#fee2e2,stroke:#dc2626,color:#111827
  classDef prom fill:#e0e7ff,stroke:#4f46e5,color:#111827
  classDef nagios fill:#ffedd5,stroke:#f97316,color:#111827
  classDef machineWeb fill:#dbeafe,stroke:#2563eb,color:#111827
  classDef machineDb fill:#dcfce7,stroke:#16a34a,color:#111827
  classDef sidecar fill:#f1f5f9,stroke:#64748b,color:#111827
  classDef exporter fill:#fef3c7,stroke:#d97706,color:#111827

  class ZBX zabbix
  class PGR prom
  class NAG nagios
  class WEB1,WEB2 machineWeb
  class PG1,PG2 machineDb
  class ZA_WEB1,ZA_WEB2,ZA_PG1,ZA_PG2 sidecar
  class NX1,NX2,PGE1,PGE2 exporter
```

Liste des sidecars Zabbix :

| Sidecar | Machine cible |
|---|---|
| `zabbix-agent-artdb01p` | `artdb01p` |
| `zabbix-agent-artzab01p` | `artzab01p` |
| `zabbix-agent-artzabweb01p` | `artzabweb01p` |
| `zabbix-agent-artweb01p` | `artweb01p` |
| `zabbix-agent-artweb02p` | `artweb02p` |
| `zabbix-agent-arthpx01p` | `arthpx01p` |
| `zabbix-agent-artbdd01p` | `artbdd01p` |
| `zabbix-agent-artbdd02p` | `artbdd02p` |
| `zabbix-agent-artglptdb01p` | `artglptdb01p` |
| `zabbix-agent-artglpt01p` | `artglpt01p` |
| `zabbix-agent-artgradb01p` | `artgradb01p` |
| `zabbix-agent-artgraidx01p` | `artgraidx01p` |
| `zabbix-agent-artgra01p` | `artgra01p` |
| `zabbix-agent-artspl01p` | `artspl01p` |
| `zabbix-agent-artrsy01p` | `artrsy01p` |
| `zabbix-agent-artsft02p` | `artsft02p` |
| `zabbix-agent-artnfs01p` | `artnfs01p` |
| `zabbix-agent-artbkp01p` | `artbkp01p` |
| `zabbix-agent-artbbx01p` | `artbbx01p` |
| `zabbix-agent-artmet01p` | `artmet01p` |
| `zabbix-agent-artpgr01p` | `artpgr01p` |
| `zabbix-agent-artgrf01p` | `artgrf01p` |
| `zabbix-agent-artnag01p` | `artnag01p` |

Liste des exporters sidecars :

| Exporter | Machine cible | Port expose dans le namespace cible |
|---|---|---:|
| `nginx-exporter-artweb01p` | `artweb01p` | `9113` |
| `nginx-exporter-artweb02p` | `artweb02p` | `9113` |
| `postgres-exporter-artbdd01p` | `artbdd01p` | `9187` |
| `postgres-exporter-artbdd02p` | `artbdd02p` | `9187` |

## 6. Flux de stockage et montages

```mermaid
flowchart LR
  HOST[Hote Docker]
  SOCK[/var/run/docker.sock/]
  DOCKERLOGS[/var/lib/docker/containers/]
  SRC[./backup/source]
  SFTPDIR[./sftp/web]
  NFSVOL[(nfs-web)]

  MET[artmet01p]
  RSY[artrsy01p]
  BKP[artbkp01p]
  SFTP[artsft02p]
  NFS[artnfs01p]

  SOCK -->|lecture stats Docker| MET
  DOCKERLOGS -->|lecture logs JSON| RSY
  SRC -->|lecture seule| BKP
  BKP -->|copie| SFTPDIR
  SFTPDIR -->|montage /home/artemis/web| SFTP
  BKP -->|copie| NFSVOL
  NFSVOL -->|export /exports/web| NFS

  classDef ext fill:#fff7ed,stroke:#ea580c,color:#111827
  classDef storage fill:#f1f5f9,stroke:#64748b,color:#111827
  classDef files fill:#e0f2fe,stroke:#0284c7,color:#111827
  classDef siem fill:#f3e8ff,stroke:#9333ea,color:#111827
  classDef sup fill:#fee2e2,stroke:#dc2626,color:#111827

  class HOST ext
  class SOCK,DOCKERLOGS,SRC,SFTPDIR,NFSVOL storage
  class BKP,SFTP,NFS files
  class RSY siem
  class MET sup
```

| Source | Destination | Type | Rôle |
|---|---|---|---|
| `/var/run/docker.sock` | `artmet01p` | Montage lecture seule | Collecte etat CPU/RAM/reseau/disque des conteneurs |
| `/var/lib/docker/containers` | `artrsy01p` | Montage lecture seule | Lecture des logs JSON Docker |
| `./backup/source` | `artbkp01p` | Montage lecture seule | Source de sauvegarde |
| `artbkp01p` | `./sftp/web` | Montage fichier | Destination sauvegarde SFTP |
| `./sftp/web` | `artsft02p` | Montage fichier | Dossier expose en SFTP |
| `artbkp01p` | `nfs-web` | Volume Docker | Destination sauvegarde NFS |
| `nfs-web` | `artnfs01p` | Volume Docker | Donnees exportees par NFS |

## 7. Dependances de demarrage principales

```mermaid
flowchart TD
  ARTDB[artdb01p] --> ZBX[artzab01p]
  ZBX --> ZBXWEB[artzabweb01p]

  WEB1[artweb01p] --> HPX[arthpx01p]
  WEB2[artweb02p] --> HPX

  PG1[artbdd01p] --> PG2[artbdd02p]
  GLPIDB[artglptdb01p] --> GLPI[artglpt01p]

  GRADB[artgradb01p] --> GRA[artgra01p]
  GRAIDX[artgraidx01p] --> GRA
  GRA --> RSY[artrsy01p]
  SPL[artspl01p] --> RSY

  SFTP[artsft02p] --> BKP[artbkp01p]
  NFS[artnfs01p] --> BKP

  PGR[artpgr01p] --> GRF[artgrf01p]

  classDef zabbix fill:#fee2e2,stroke:#dc2626,color:#111827
  classDef web fill:#dbeafe,stroke:#2563eb,color:#111827
  classDef db fill:#dcfce7,stroke:#16a34a,color:#111827
  classDef itsm fill:#fef3c7,stroke:#d97706,color:#111827
  classDef siem fill:#f3e8ff,stroke:#9333ea,color:#111827
  classDef files fill:#e0f2fe,stroke:#0284c7,color:#111827
  classDef sup fill:#e0e7ff,stroke:#4f46e5,color:#111827

  class ARTDB,ZBX,ZBXWEB zabbix
  class WEB1,WEB2,HPX web
  class PG1,PG2 db
  class GLPIDB,GLPI itsm
  class GRADB,GRAIDX,GRA,SPL,RSY siem
  class SFTP,NFS,BKP files
  class PGR,GRF sup
```

Ces dependances correspondent aux `depends_on` principaux du `docker-compose.yml`. Les sidecars Zabbix et exporters dependent aussi de leur machine cible.
