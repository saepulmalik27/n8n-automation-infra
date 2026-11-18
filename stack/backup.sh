#!/usr/bin/env bash
# Daily dump of all databases (n8n, knowledge, english_tutor); keeps 7 days on the server.
set -euo pipefail
mkdir -p ~/backups
cd ~/n8n
docker compose exec -T postgres pg_dumpall -U n8n | gzip > ~/backups/pg-$(date +%F).sql.gz
find ~/backups -name 'pg-*.sql.gz' -mtime +7 -delete

# Off-VPS copy to Cloudflare R2, so losing the VM doesn't lose the backups. The VPS keeps 7 days;
# R2 keeps every copy unless the bucket has a lifecycle rule. Skipped until R2_* are in .env.
# NO_HEAD: rclone 1.60 checks uploads with HEAD ?versionId=, which R2 answers 501.
set -a; source ~/n8n/.env; set +a
if [[ -n "${R2_BUCKET:-}" ]]; then
  RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare RCLONE_CONFIG_R2_ENDPOINT="$R2_ENDPOINT" \
  RCLONE_CONFIG_R2_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
  RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true \
  RCLONE_CONFIG_R2_NO_HEAD=true \
    rclone copy ~/backups "r2:$R2_BUCKET/pg" --include 'pg-*.sql.gz'
fi
