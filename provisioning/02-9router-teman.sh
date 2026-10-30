#!/usr/bin/env bash
# Jalankan sebagai ngemis:  bash 02-9router-teman.sh <username>
set -euo pipefail
U="${1:?pakai: bash 02-9router-teman.sh <username>}"
UID_T=$(id -u "$U")
PORT=20129

D="/home/${U}/9router-data"
mkdir -p "$D"
chown -R "${UID_T}:${UID_T}" "$D"
chmod 700 "$D"

if sg docker -c "docker inspect 9router-teman" &>/dev/null; then
  echo "container 9router-teman sudah ada; restart saja"
  sg docker -c "docker restart 9router-teman"
else
  sg docker -c "docker run -d \
    --name 9router-teman \
    --restart unless-stopped \
    --user ${UID_T}:${UID_T} \
    --memory 512m --cpus 0.75 \
    -p 127.0.0.1:${PORT}:20128 \
    -v ${D}:/app/data \
    decolua/9router:latest"
fi

sleep 5
echo "== status"
sg docker -c "docker ps --filter name=9router-teman --format '{{.Names}} {{.Status}} {{.Ports}}'"
echo "Control panel: ssh -L ${PORT}:127.0.0.1:${PORT} <user>@<ip-server>  lalu buka http://127.0.0.1:${PORT}"
