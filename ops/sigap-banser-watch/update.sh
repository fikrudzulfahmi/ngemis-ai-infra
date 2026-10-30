#!/usr/bin/env bash
# Update manual SIGAP BANSER: pull dari GitHub, siapkan ulang cache, restart app.
# Panggil sendiri kapan pun mau ambil kode terbaru:  ~/sigap-banser-watch/update.sh
set -uo pipefail

APP="$HOME/sigap-banser"
BRANCH="${BRANCH:-main}"
cd "$APP" || exit 1

OPEN=$(git rev-parse --verify --quiet HEAD || true)
LOCK_BEFORE=$(md5sum composer.lock 2>/dev/null | cut -d' ' -f1)

# file cache bootstrap ikut ter-commit di repo & berubah tiap composer install -> buang dulu biar pull tidak bentrok
git checkout -- bootstrap/cache 2>/dev/null || true

if ! git pull --ff-only origin "$BRANCH"; then
    echo "!! pull --ff-only gagal (riwayat di server berbeda). Pakai reset keras:"
    echo "   cd $APP && git fetch origin && git reset --hard origin/$BRANCH"
    exit 1
fi

NEW=$(git rev-parse HEAD)
[ "$OPEN" = "$NEW" ] && echo "== tidak ada perubahan (sudah versi terbaru: $(git log -1 --format='%h %s'))" || echo "== update ke $(git log -1 --format='%h %s')"

# dependency PHP kalau composer.lock berubah (atau vendor belum ada)
LOCK_AFTER=$(md5sum composer.lock 2>/dev/null | cut -d' ' -f1)
if [ ! -d vendor ] || [ "$LOCK_BEFORE" != "$LOCK_AFTER" ]; then
    echo "== composer install"
    composer install --no-interaction --prefer-dist || exit 1
fi

# storage/ tidak ikut di repo, pastikan ada
mkdir -p storage/app/public storage/framework/{cache/data,sessions,views} storage/logs
chmod -R ug+rwX storage bootstrap/cache

# migrasi baru (aman diulang, tidak menghapus data)
php artisan migrate --force || exit 1

# cache dibangun ulang supaya route/view baru ikut terpakai
php artisan optimize:clear >/dev/null
php artisan config:cache >/dev/null
php artisan route:cache >/dev/null
php artisan view:cache >/dev/null

systemctl --user restart sigap-banser.service
sleep 2
echo "== service: $(systemctl --user is-active sigap-banser.service) | port 8088 | $(curl -s -o /dev/null -w 'HTTP %{http_code}' http://127.0.0.1:8088/login)"
