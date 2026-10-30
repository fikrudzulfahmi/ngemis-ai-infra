#!/bin/bash
# Backup seluruh konfigurasi + database sebelum instal ulang ngemis-ai.
# Jalankan:  sudo bash scripts/backup-before-reinstall.sh
# Hasil   :  /var/backups/ngemis-ai-<tanggal>.tar.gz
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "Jalankan dengan sudo"; exit 1; }

USER_HOME="/home/ngemis"
TS="$(date +%Y%m%d-%H%M%S)"
WORK="$(mktemp -d)"
OUT="/var/backups/ngemis-ai-$TS.tar.gz"
mkdir -p "$WORK"/{config,env,db,lists}
say() { printf '  - %s\n' "$*"; }

echo "== 1. Database MySQL"
if mysqldump --all-databases --single-transaction --routines --triggers \
      --events --default-character-set=utf8mb4 > "$WORK/db/all-databases.sql" 2>"$WORK/db/err.log"; then
  say "dump semua database OK ($(du -h "$WORK/db/all-databases.sql" | cut -f1))"
else
  say "PERINGATAN: dump gagal, lihat db/err.log"
fi
mysql -N -e "SELECT user,host FROM mysql.user" > "$WORK/db/users.txt" 2>/dev/null
mysql -N -e "SHOW DATABASES" > "$WORK/db/databases.txt" 2>/dev/null

echo "== 2. File .env & konfigurasi aplikasi"
for d in cms-tsm cms-tkr siber au-backend wa-gateway sigap-banser cctv server-monitor printserver; do
  [ -f "$USER_HOME/$d/.env" ] && cp -a "$USER_HOME/$d/.env" "$WORK/env/$d.env" && say "env $d"
done
cp -a "$USER_HOME/cctv/cameras.json" "$WORK/config/" 2>/dev/null
cp -a "$USER_HOME/cctv/users.json"   "$WORK/config/" 2>/dev/null
cp -a "$USER_HOME/cctv/.secret"      "$WORK/config/" 2>/dev/null

echo "== 3. Konfigurasi sistem"
cp -a /etc/nginx/sites-available "$WORK/config/nginx-sites-available"
cp -a /etc/systemd/system/print910*.socket /etc/systemd/system/print9101@.service \
      /etc/systemd/system/cloudflared.service "$WORK/config/" 2>/dev/null
mkdir -p "$WORK/config/systemd-user"
cp -a "$USER_HOME"/.config/systemd/user/*.service "$WORK/config/systemd-user/" 2>/dev/null
cp -a /etc/sudoers.d "$WORK/config/sudoers.d"
cp -a /etc/cups "$WORK/config/cups" 2>/dev/null
cp -a /etc/fstab "$WORK/config/fstab"
cp -a /etc/samba/smb.conf "$WORK/config/smb.conf" 2>/dev/null
cp -a /etc/systemd/resolved.conf.d "$WORK/config/resolved.conf.d" 2>/dev/null

echo "== 4. Token & identitas"
cp -a /etc/cloudflared/token "$WORK/config/cloudflared-token" 2>/dev/null && say "token cloudflared"
[ -f /var/lib/tailscale/tailscale.state ] && cp -a /var/lib/tailscale/tailscale.state "$WORK/config/" && say "state tailscale"
cp -a /opt/9router/data "$WORK/config/9router-data" 2>/dev/null && say "data 9router"

echo "== 5. Daftar paket & service (untuk rebuild)"
dpkg --get-selections > "$WORK/lists/packages.txt"
apt-mark showmanual > "$WORK/lists/packages-manual.txt"
systemctl list-unit-files --state=enabled > "$WORK/lists/units-enabled.txt"
docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}' > "$WORK/lists/docker-ps.txt" 2>/dev/null
crontab -l > "$WORK/lists/crontab-root.txt" 2>/dev/null
sudo -u ngemis crontab -l > "$WORK/lists/crontab-ngemis.txt" 2>/dev/null
lsblk -o NAME,SIZE,MODEL,SERIAL,UUID,FSTYPE,MOUNTPOINTS > "$WORK/lists/lsblk.txt"

echo "== 6. Hermes (skills/config, tanpa session)"
if [ -d "$USER_HOME/.hermes" ]; then
  tar -C "$USER_HOME" -czf "$WORK/config/hermes-min.tar.gz" \
      --exclude='.hermes/sessions' --exclude='.hermes/cache' --exclude='.hermes/logs' \
      .hermes 2>/dev/null && say "hermes (skills+config)"
fi

chmod -R go-rwx "$WORK"
tar -C "$WORK" -czf "$OUT" . && chmod 600 "$OUT"
rm -rf "$WORK"
echo
echo "SELESAI: $OUT ($(du -h "$OUT" | cut -f1))"
echo "Salin ke PC:  scp ngemis@<ip>:$OUT ."
echo "PERIKSA: file ini berisi semua rahasia server. Simpan di tempat aman, jangan di-commit."
