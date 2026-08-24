#!/usr/bin/env bash
set -euo pipefail
umask 077

readonly project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly dev_root="$project_root/_dev"
readonly template="$project_root/tools/broadcast-dev/SiteConfig.yml"
readonly marker="$dev_root/.broadcast-dev-configured"
readonly secrets="$dev_root/.maverick-secrets"
readonly dev_port="${MAVERICK_DEV_PORT:-8080}"

if [[ ! "$dev_port" =~ ^[0-9]+$ ]] || ((dev_port < 1 || dev_port > 65535)); then
    echo "MAVERICK_DEV_PORT must be a TCP port between 1 and 65535" >&2
    exit 1
fi

if [[ ! -d "$dev_root/Public" || ! -d "$dev_root/Resources" ]]; then
    echo "The _dev site is missing. Run 'mise run dev' once, then retry." >&2
    exit 1
fi

if [[ ! -f "$marker" ]]; then
    if [[ -f "$dev_root/SiteConfig.yml" ]]; then
        cp "$dev_root/SiteConfig.yml" "$dev_root/SiteConfig.before-broadcast.yml"
    fi
    touch "$marker"
fi
sed "s/__MAVERICK_DEV_PORT__/$dev_port/g" "$template" >"$dev_root/SiteConfig.yml"

mkdir -p "$secrets" "$dev_root/.maverick-data"

if [[ ! -s "$secrets/maverick-admin-username" ]]; then
    printf '%s' "admin" >"$secrets/maverick-admin-username"
fi
if [[ ! -s "$secrets/maverick-admin-password" ]]; then
    openssl rand -hex 12 >"$secrets/maverick-admin-password"
fi
if [[ ! -s "$secrets/maverick-state-encryption-key" ]]; then
    openssl rand -base64 32 >"$secrets/maverick-state-encryption-key"
fi
chmod 600 "$secrets"/*

echo "Local broadcaster configuration is ready."
echo "Admin URL:      http://127.0.0.1:$dev_port/_admin/broadcast"
echo "Admin username: $(<"$secrets/maverick-admin-username")"
echo "Admin password: $(<"$secrets/maverick-admin-password")"
echo "State:          $dev_root/.maverick-data/broadcast-state"
echo "Provider credentials are optional until you test real connections or sends."
