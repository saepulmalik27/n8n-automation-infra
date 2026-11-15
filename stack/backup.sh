#!/usr/bin/env bash
# Daily dump of all databases (n8n + knowledge); keeps 7 days on the server.
set -euo pipefail
mkdir -p ~/backups
cd ~/n8n
docker compose exec -T postgres pg_dumpall -U n8n | gzip > ~/backups/pg-$(date +%F).sql.gz
find ~/backups -name 'pg-*.sql.gz' -mtime +7 -delete
