# Suivi des travaux Artemis

Ce fichier suit les choix et l'avancement technique du lab. Il sert de note de travail et ne remplace pas les livrables dans `Livrables/`.

## Périmètre retenu

- Objectif principal : comparer les apports de Zabbix, Nagios et Prometheus/Grafana sur un lab reproductible.
- Déploiement en conteneurs Docker Compose assumé pour simplifier les tests.
- Réseau volontairement simplifié : pas de VLAN, pas de VIP et pas de séparation physique des zones.
- Hors périmètre volontaire pour garder le lab lisible : SMTP, LDAP/annuaire, VIP HAProxy.
- Backup à reprendre plus tard : la preuve actuelle reste conservée sans refonte fonctionnelle.
- `Livrables/Projet Artemis.docx` sert uniquement de contexte et ne doit pas être modifié ici.

## À faire

- [x] Ajouter un cluster PostgreSQL Artemis primaire/réplique (`artbdd01p`, `artbdd02p`).
- [x] Exposer les métriques PostgreSQL dans Prometheus.
- [x] Ajouter le taux d'occupation disque/volume.
- [x] Étendre la couverture Zabbix aux services du lab.
- [x] Séparer les alertes Grafana par domaine fonctionnel.
- [x] Valider la configuration Compose et documenter les points restants.

## Fait

- [x] Clarification du périmètre volontairement simplifié.
- [x] Création de cette note de suivi.
- [x] Ajout des services `artbdd01p` et `artbdd02p` avec réplication PostgreSQL primaire/réplique.
- [x] Ajout des exporters PostgreSQL Prometheus.
- [x] Ajout des métriques `artemis_volume_*` dans l'exporter Docker.
- [x] Ajout des agents Zabbix pour les services applicatifs, fichiers, supervision et BDD.
- [x] Extension du bootstrap Zabbix aux hôtes du lab.
- [x] Ajout d'items Zabbix applicatifs simples pour les ports et endpoints importants.
- [x] Enrichissement du dashboard Zabbix : statuts applicatifs, CPU/RAM par tiers, réseau, Nginx, HAProxy, PostgreSQL et supervision.
- [x] Enrichissement Nagios : 17 hôtes et 54 services, avec checks HTTP contenus/exporters, rôles PostgreSQL, backup et pile de supervision.
- [x] Remplacement de l'alerte Grafana unique par des règles séparées : frontend, web, fichiers, base de données, backup, capacité et supervision.
- [x] Remplacement de l'image PostgreSQL Bitnami prévue initialement par `postgres:16-alpine` avec scripts de réplication locaux.
- [x] Déplacement du script de preuve de sauvegarde `artbkp01p` dans `backup/run-backup.sh` pour garder `docker-compose.yml` lisible.
- [x] Validation du démarrage complet avec `./up.sh --build`.
- [x] Validation Prometheus : exporters PostgreSQL et métriques disque visibles.
- [x] Validation PostgreSQL : `artbdd01p` primaire, `artbdd02p` en recovery, réplication de données testée.

## Restera volontairement ouvert

- Refactor de la sauvegarde réelle via SFTP/NFS client.
- Ajout éventuel d'un axe logs/SIEM avec Graylog, Rsyslog ou Splunk.
- Notifications d'alertes Grafana.
- Livrables RAO hors code : présentation, DEX, plan financier, planning projet.
- Nettoyage éventuel de l'ancien export `zabbix/hosts-artemis.xml`, non utilisé par `./up.sh`.
