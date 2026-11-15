#!/usr/bin/env bash
#
# Upload stack/ to ~/n8n on the Oracle VPS and (re)start it.
# Use after the first setup whenever stack/ changes (e.g. an n8n upgrade).
# Reads server address and secrets from ~/.config/oracle-n8n/.env, which
# scripts/setup-oracle.sh writes. Safe to re-run: volumes and data stay.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$HOME/.config/oracle-n8n/.env}"

[[ -f "$ENV_FILE" ]] || { echo "missing $ENV_FILE: run scripts/setup-oracle.sh first" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
for k in OCI_PUBLIC_IP OCI_SSH_KEY POSTGRES_PASSWORD N8N_ENCRYPTION_KEY; do
  [[ -n "${!k:-}" ]] || { echo "$k is empty in $ENV_FILE" >&2; exit 1; }
done

target="ubuntu@$OCI_PUBLIC_IP"
opts=(-i "$OCI_SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)

# Refuse to overwrite a server key that differs from the local one: n8n
# credentials encrypted with the server key would become unreadable.
remote_key=$(ssh "${opts[@]}" "$target" "grep -E '^N8N_ENCRYPTION_KEY=' ~/n8n/.env 2>/dev/null | cut -d= -f2-" || true)
if [[ -n "$remote_key" && "$remote_key" != "$N8N_ENCRYPTION_KEY" ]]; then
  echo "N8N_ENCRYPTION_KEY on the server differs from $ENV_FILE; aborting." >&2
  exit 1
fi

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
( umask 077; {
  printf 'POSTGRES_PASSWORD=%s\nN8N_ENCRYPTION_KEY=%s\n' "$POSTGRES_PASSWORD" "$N8N_ENCRYPTION_KEY"
  # Public domain through Cloudflare Tunnel (scripts/setup-domain.sh writes these).
  if [[ -n "${N8N_DOMAIN:-}" && -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]]; then
    printf 'N8N_HOST=%s\nN8N_PROTOCOL=https\nN8N_EDITOR_BASE_URL=https://%s/\nN8N_WEBHOOK_URL=https://%s/\n' \
      "$N8N_DOMAIN" "$N8N_DOMAIN" "$N8N_DOMAIN"
    printf 'N8N_PROXY_HOPS=1\nCLOUDFLARE_TUNNEL_TOKEN=%s\nCOMPOSE_PROFILES=tunnel\n' "$CLOUDFLARE_TUNNEL_TOKEN"
  fi
} > "$tmp/.env" )
[[ -n "${N8N_DOMAIN:-}" && -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]] \
  && echo "→ public domain: https://$N8N_DOMAIN (Cloudflare Tunnel)" \
  || echo "→ no public domain: n8n stays reachable only through the SSH tunnel"

echo "→ uploading stack/ to $target:~/n8n"
ssh "${opts[@]}" "$target" 'mkdir -p ~/n8n/init && chmod 700 ~/n8n'
scp "${opts[@]}" -q "$REPO_DIR/stack/docker-compose.yml" "$REPO_DIR/stack/backup.sh" "$tmp/.env" "$target:n8n/"
scp "${opts[@]}" -q "$REPO_DIR"/stack/init/*.sql "$target:n8n/init/"

echo "→ starting containers"
ssh "${opts[@]}" "$target" 'chmod 600 ~/n8n/.env && chmod +x ~/n8n/backup.sh && cd ~/n8n && docker compose pull -q && docker compose up -d --remove-orphans && docker compose ps'
