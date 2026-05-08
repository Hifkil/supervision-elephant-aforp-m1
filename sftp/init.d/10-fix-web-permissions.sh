#!/usr/bin/env bash
set -euo pipefail

mkdir -p /home/artemis/web
chown -R 1001:100 /home/artemis/web
chmod 0755 /home/artemis/web
