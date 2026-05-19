# Completion du stack Artemis

Ce fichier suit les derniers points a traiter pour considerer le stack de supervision comme complet cote code et demonstration. Il ne remplace pas les livrables dans `Livrables/`.

## P0 - A terminer avant rendu

- [ ] Faire un test de reset complet : `docker compose down -v`, puis `./up.sh --build`.
- [ ] Verifier apres reset que Zabbix recree bien tous les hosts, items simples et le dashboard Artemis.
- [ ] Verifier apres reset que Nagios charge toujours les 24 hosts et 72 services sans erreur.
- [ ] Verifier que Prometheus voit toutes les targets attendues : HAProxy, Nginx, PostgreSQL, GLPI/MySQL, SIEM/logs, Blackbox, backup et Docker metrics.
- [ ] Verifier que Graylog recoit des logs via l'input `Artemis syslog TCP`.
- [ ] Verifier que Splunk recoit des logs dans l'index `artemis`.
- [ ] Prendre les captures necessaires pour le dossier ou la presentation : Zabbix dashboard, Nagios services, Grafana dashboard, Prometheus targets, GLPI, Graylog, Splunk.
- [ ] Rejouer un scenario de panne simple pour chaque outil :
  - arreter un backend Nginx et observer HAProxy, Nagios, Zabbix, Grafana ;
  - arreter la replique PostgreSQL et observer les checks DB ;
  - arreter `artglpt01p` ou `artglptdb01p` et observer les checks GLPI ;
  - arreter `artrsy01p`, `artgry01p` ou `artspl01p` et observer les checks SIEM/logs ;
  - arreter `artbkp01p` et observer backup/exporter.

## P1 - Ameliorations utiles si temps disponible

- [ ] Remplacer la preuve de backup par un vrai flux SFTP/NFS client si le temps le permet.
- [ ] Ajouter un petit generateur de trafic HTTP pour rendre les graphes HAProxy/Nginx plus visuels pendant la demo.
- [ ] Ajouter un script de verification rapide qui lance les checks principaux apres demarrage.
- [ ] Documenter en une page la difference entre ce que Zabbix, Nagios et Prometheus/Grafana apportent dans le lab.
- [ ] Nettoyer ou supprimer `zabbix/hosts-artemis.xml` si l'export n'est plus utilise.

## P2 - Hors perimetre actuel

- [ ] Notifications d'alertes Grafana/Zabbix/Nagios.
- [ ] Sauvegarde externalisee robuste avec retention.
- [ ] SMTP, LDAP/annuaire, VIP HAProxy et segmentation reseau.
- [ ] Livrables RAO hors code : presentation, DEX, plan financier, planning projet.

## Definition de termine

- [ ] Le stack repart depuis zero avec une seule commande `./up.sh --build`.
- [ ] Les dashboards Zabbix et Grafana affichent des donnees exploitables.
- [ ] Nagios affiche les services principaux en OK.
- [ ] Les seuils principaux sont documentes dans `SUPERVISION_THRESHOLDS.md`.
- [ ] Les choix de simplification sont explicites dans la documentation.
