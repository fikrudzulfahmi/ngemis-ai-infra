#!/usr/bin/env bash
# Jalankan SEBAGAI user teman (bukan root):  bash /home/ngemis/setup-teman/03-hermes-teman.sh
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "JANGAN dijalankan sebagai root"; exit 1; }

echo "== 1) install Hermes (per-user, masuk ~/.hermes)"
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash

export PATH="$HOME/.local/bin:$PATH"

echo "== 2) arahkan ke 9Router milik sendiri (port 20129)"
cat <<'TIP'

Setelah ini jalankan manual:
  hermes setup            # atau: hermes model  -> pilih custom provider
  base_url : http://127.0.0.1:20129/v1
  api key  : key yang kamu buat di control panel 9Router kamu
  hermes gateway setup    # masukkan token bot Telegram milikmu sendiri
  hermes gateway start
  systemctl --user enable --now hermes-gateway.service
TIP
