#!/usr/bin/env bash
set -euo pipefail

sudo mkdir -p /opt/splunk/etc/apps/artemis
sudo cp -a /opt/artemis-splunk-app/. /opt/splunk/etc/apps/artemis/
if sudo grep -q '00000000-0000-0000-0000-000000000000' /opt/splunk/etc/apps/splunk_httpinput/local/inputs.conf 2>/dev/null; then
  sudo rm -f /opt/splunk/etc/apps/splunk_httpinput/local/inputs.conf
fi
sudo chown -R ansible:ansible /opt/splunk/etc/apps/artemis

exec /sbin/entrypoint.sh "$@"
