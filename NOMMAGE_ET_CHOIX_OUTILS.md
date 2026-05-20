# Nommage Artemis et choix de supervision

Ce document fixe les noms de machines utilisés par la maquette et explique les écarts assumés par rapport au sujet.

## Périmètre volontairement simplifié

Le sujet présente une architecture complète avec deux HAProxy, une VIP, des VLAN, un SMTP et un annuaire. Ces points sont volontairement hors périmètre pour cette maquette étudiante : l'objectif est de démontrer une supervision cohérente et exploitable, pas de reproduire toute l'architecture réseau Artemis.

Ne sont donc pas simulés :

- le deuxième HAProxy et la VIP ;
- la segmentation VLAN ;
- `artsmt01p` pour le SMTP ;
- `artann01p` pour l'annuaire/LDAP.

Ces absences doivent être présentées comme des choix de cadrage, pas comme des oublis.

## Noms canoniques

| Nom du sujet | Rôle | Statut dans la maquette | Remarque |
|---|---|---|---|
| `arthpx01p` | HAProxy | Implémenté | Un seul HAProxy, sans VIP. |
| `artweb01p` | Web 1 | Implémenté | Backend Nginx. |
| `artweb02p` | Web 2 | Implémenté | Backend Nginx. |
| `artsft02p` | SFTP | Implémenté | Cible de sauvegarde web. |
| `artnfs01p` | NFS | Implémenté | Cible de sauvegarde web. |
| `artbdd01p` | BDD primaire | Implémenté | PostgreSQL primaire. |
| `artbdd02p` | BDD secondaire | Implémenté | PostgreSQL réplique. |
| `artglpt01p` | GLPI | Implémenté | Ancien nom erroné `artglp01p` à supprimer de Zabbix. |
| `artgra01p` | Graylog | Implémenté | Remplace l'ancien nom de maquette `artgry01p`. |
| `artpgr01p` | Prometheus / Grafana | Implémenté partiellement | Prometheus porte le nom sujet ; Grafana reste séparé en `artgrf01p` pour la maquette Docker. |
| `artrsy01p` | Rsyslog | Implémenté | Relais logs vers Graylog et Splunk. |
| `artsmt01p` | SMTP | Non simulé | Hors périmètre étudiant. |
| `artann01p` | Annuaire | Non simulé | Hors périmètre étudiant. |

## Conteneurs techniques ajoutés

Certains conteneurs n'existent pas comme machines dans le sujet, mais sont nécessaires pour faire fonctionner les outils dans Docker :

- `artglptdb01p` : base MySQL dédiée de GLPI ;
- `artgradb01p` : MongoDB utilisé par Graylog ;
- `artgraidx01p` : OpenSearch utilisé par Graylog ;
- `artgrf01p` : interface Grafana séparée de Prometheus ;
- `artzab01p`, `artzabweb01p`, `artdb01p` : pile Zabbix ;
- `artnag01p` : Nagios ;
- `artbbx01p` : Blackbox Exporter ;
- `artmet01p` : exporter de métriques Docker ;
- `artbkp01p` : preuve de sauvegarde.

## Nettoyage Zabbix

Le bootstrap Zabbix supprime désormais les anciens noms connus avant de créer les hosts canoniques :

- `artglp01p` et `artglpdb01p` ;
- `artgry01p`, `artgrydb01p`, `artgryidx01p` ;
- `artprom01p`.

Cela évite l'erreur du type :

```text
Get value from agent failed: Cannot resolve address: Timeout while contacting DNS servers
```

Après changement de nom, relancer :

```bash
docker compose up -d --remove-orphans
./zabbix/setup-hosts.sh
./zabbix/setup-dashboard.py
```

## Rôle des outils

Le lab utilise plusieurs outils volontairement, mais chacun a un rôle distinct :

| Outil | Rôle dans la maquette | Justification |
|---|---|---|
| Zabbix | Supervision infra et applicative par agents | Vue d'exploitation centrale : disponibilité agents, CPU/RAM/disque, ports applicatifs et dashboard Artemis. |
| Nagios | Contrôles actifs simples | Démonstration claire des états `OK/WARNING/CRITICAL` sur HTTP, TCP, contenus et rôles PostgreSQL. |
| Prometheus | Collecte de métriques numériques | Métrologie et capacity planning : exporters HAProxy, Nginx, PostgreSQL, Blackbox, backup et métriques Docker. |
| Grafana | Visualisation et alertes | Dashboard métier lisible pour comparer disponibilité, latence, ressources et tendances. |
| Blackbox Exporter | Tests externes HTTP/TCP/ICMP | Vérifie le service rendu depuis l'extérieur du composant, pas seulement l'état du conteneur. |
| Rsyslog | Collecteur et relais de logs | Centralise les logs Docker/syslog et les transmet aux outils SIEM. |
| Graylog | SIEM/log management principal | Recherche et analyse des événements centralisés. |
| Splunk | Outil SIEM comparatif | Sert de comparaison et de seconde destination de logs dans la démonstration. |
| GLPI | ITSM | Représente le suivi opérationnel des incidents et actifs, même sans workflow complet. |

La phrase à défendre à l'oral : Zabbix et Nagios montrent l'état instantané et les alertes, Prometheus/Grafana portent la métrologie et le capacity planning, Graylog/Splunk couvrent les logs et l'analyse d'incident, GLPI matérialise la partie exploitation.
