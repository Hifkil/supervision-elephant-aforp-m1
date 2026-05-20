# Scénarios de panne pour la démonstration

Ces scénarios servent à montrer que la maquette Artemis détecte une panne, conserve le service quand c'est possible et permet de revenir à l'état nominal.

Le déroulé est automatisé par `./run-scenario.sh`. Ce document reste utile pour savoir quoi regarder dans chaque interface.

Avant de commencer :

```bash
./up.sh
docker compose ps
./run-scenario.sh urls
```

Ouvrir les interfaces utiles :

| Outil | URL |
|---|---|
| HAProxy | http://localhost |
| HAProxy stats | http://localhost:8404/stats |
| Zabbix | http://localhost:8080 |
| Nagios | http://localhost:8081/nagios |
| Prometheus targets | http://localhost:9090/targets |
| Grafana | http://localhost:3000 |
| Graylog | http://localhost:9000 |

Les checks Nagios et Zabbix ne basculent pas toujours immédiatement. Attendre 1 à 2 minutes après l'injection d'une panne pour voir les états se stabiliser.

## Scénario 1 - Perte d'un backend web

### Objectif

Montrer que la perte de `artweb01p` est détectée et que HAProxy continue de servir le site via `artweb02p`.

### État attendu avant panne

```bash
docker compose ps artweb01p artweb02p arthpx01p
curl -s http://localhost
```

Résultat attendu : les deux backends web sont `healthy` et le site répond via HAProxy.

### Injection de panne

```bash
./run-scenario.sh web-down
```

### À observer

| Outil | Observation attendue |
|---|---|
| HAProxy stats | `artweb01p` passe `DOWN`, `artweb02p` reste `UP`. |
| HAProxy web | `http://localhost` répond encore, servi uniquement par `artweb02p`. |
| Nagios | `artweb01p` passe en panne sur `PING`, `HTTP`, `Nginx Status` et exporter. |
| Zabbix | l'agent `artweb01p` devient indisponible et les items Nginx ne remontent plus. |
| Prometheus | `probe_success{instance="http://artweb01p"}` passe à `0`, les métriques HAProxy indiquent un backend down. |
| Grafana | la section HAProxy/backends montre un backend indisponible. |

Commande rapide de preuve :

```bash
curl -s http://localhost
```

La réponse doit rester disponible malgré la panne d'un backend.

### Retour à la normale

```bash
./run-scenario.sh web-restore
```

Attendre le retour `healthy`, puis vérifier :

```bash
docker compose ps artweb01p nginx-exporter-artweb01p zabbix-agent-artweb01p
curl -s http://localhost
```

## Scénario 2 - Perte de la réplique PostgreSQL

### Objectif

Montrer que la supervision détecte la perte de la réplique `artbdd02p`, sans arrêter le primaire `artbdd01p`.

### État attendu avant panne

```bash
docker compose ps artbdd01p artbdd02p
docker compose exec -T artbdd01p psql -U artemis -d artemis -c "select pg_is_in_recovery();"
docker compose exec -T artbdd02p psql -U artemis -d artemis -c "select pg_is_in_recovery();"
```

Résultat attendu :

- `artbdd01p` retourne `f` : primaire ;
- `artbdd02p` retourne `t` : réplique.

### Injection de panne

```bash
./run-scenario.sh db-down
```

### À observer

| Outil | Observation attendue |
|---|---|
| Nagios | `artbdd02p` passe en panne sur `PING`, `PostgreSQL TCP`, exporter PostgreSQL et rôle réplique. |
| Zabbix | agent `artbdd02p` indisponible, port PostgreSQL en échec. |
| Prometheus | target `postgres` de `artbdd02p:9187` down ou absente, probe TCP `artbdd02p:5432` à `0`. |
| Grafana | section base de données : réplique indisponible, primaire toujours visible. |
| Service | `artbdd01p` reste disponible. |

Commande rapide de preuve :

```bash
docker compose exec -T artbdd01p pg_isready -U artemis -d artemis -h 127.0.0.1
```

Le primaire doit rester `accepting connections`.

### Retour à la normale

```bash
./run-scenario.sh db-restore
```

Attendre le retour `healthy`, puis vérifier :

```bash
docker compose ps artbdd02p postgres-exporter-artbdd02p zabbix-agent-artbdd02p
docker compose exec -T artbdd02p psql -U artemis -d artemis -c "select pg_is_in_recovery();"
```

La réplique doit de nouveau retourner `t`.

## Scénario 3 - Perte de la chaîne SIEM / logs

### Objectif

Montrer que la perte du collecteur `artrsy01p` coupe le relais des logs vers Graylog/Splunk, tout en laissant les plateformes SIEM disponibles.

Ce scénario est plus lisible qu'un arrêt complet de Graylog, car il isole le composant de collecte et évite d'attendre le redémarrage long de Graylog/OpenSearch.

### État attendu avant panne

```bash
docker compose ps artrsy01p artgra01p artspl01p
curl -s http://localhost:9000/api/system/lbstatus
```

Résultat attendu : `artrsy01p`, `artgra01p` et `artspl01p` sont démarrés, Graylog répond `ALIVE`.

Optionnel, envoyer un log de test avant panne :

```bash
logger -n 127.0.0.1 -P 10514 -T "artemis demo log avant panne"
```

### Injection de panne

```bash
./run-scenario.sh siem-down
```

### À observer

| Outil | Observation attendue |
|---|---|
| Nagios | `artrsy01p` passe en panne sur `PING` et `Rsyslog TCP`. |
| Zabbix | agent `artrsy01p` indisponible, check TCP `514` en échec. |
| Prometheus | probe TCP `artrsy01p:514` à `0`. |
| Grafana | section SIEM/logs : collecteur Rsyslog indisponible. |
| Graylog/Splunk | interfaces encore accessibles, mais les nouveaux logs ne transitent plus via Rsyslog. |

Commande rapide de preuve :

```bash
docker compose ps artrsy01p
```

Le service doit être arrêté.

### Retour à la normale

```bash
./run-scenario.sh siem-restore
```

Attendre le retour du port `514`, puis vérifier :

```bash
docker compose ps artrsy01p zabbix-agent-artrsy01p
docker compose exec -T artzab01p zabbix_get -s artrsy01p -k agent.ping
```

Résultat attendu : `1`.

Envoyer un log de test après retour :

```bash
logger -n 127.0.0.1 -P 10514 -T "artemis demo log apres retour rsyslog"
```

## Commandes de contrôle global

Après chaque scénario, contrôler rapidement :

```bash
docker compose ps
docker compose exec -T artnag01p nagios -v /opt/nagios/etc/nagios.cfg
curl -s http://localhost:9090/-/healthy
```

Si un sidecar Zabbix ou exporter reste indisponible après redémarrage d'un service, le recréer :

```bash
docker compose up -d --force-recreate --no-deps <sidecar>
```

Exemple :

```bash
docker compose up -d --force-recreate --no-deps nginx-exporter-artweb01p
docker compose up -d --force-recreate --no-deps zabbix-agent-artweb01p
```
