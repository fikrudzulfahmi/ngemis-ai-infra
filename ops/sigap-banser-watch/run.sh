#!/usr/bin/env bash
# Menjalankan app sigap-banser di 127.0.0.1:8088 (dipakai cloudflared tunnel).
# Entrypoint dideteksi otomatis: PHP (public/index.php) atau Node (package.json).
set -uo pipefail

APP_DIR="$HOME/sigap-banser"
PORT="${PORT:-8088}"
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
export NODE_ENV="${NODE_ENV:-production}"

cd "$APP_DIR" || exit 1

if [ ! -d .git ] || [ -z "$(ls -A . 2>/dev/null | grep -v '^.git$')" ]; then
    echo "$(date '+%F %T') belum ada kode di $APP_DIR (menunggu push pertama)"
    sleep 30
    exit 0
fi

if [ -f artisan ]; then
    [ -f public/index.php ] && exec php -S "127.0.0.1:$PORT" -t public
fi

if [ -f public/index.php ]; then
    exec php -S "127.0.0.1:$PORT" -t public
fi

if [ -f index.php ]; then
    exec php -S "127.0.0.1:$PORT" -t .
fi

if [ -f package.json ]; then
    if grep -q '"start"[[:space:]]*:' package.json; then
        exec npm start -- --port "$PORT" --host 127.0.0.1
    fi
    if grep -q '"dev"[[:space:]]*:' package.json; then
        exec npm run dev -- --port "$PORT" --host 127.0.0.1
    fi
fi

echo "$(date '+%F %T') tidak ada entrypoint yang dikenali (index.php / package.json)"
sleep 30
exit 0
