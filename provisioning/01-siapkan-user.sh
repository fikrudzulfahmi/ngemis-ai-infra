#!/usr/bin/env bash
# Jalankan sebagai root:  sudo bash 01-siapkan-user.sh <username>
set -euo pipefail
U="${1:?pakai: sudo bash 01-siapkan-user.sh <username>}"

if id "$U" &>/dev/null; then
  echo "user $U sudah ada"
else
  adduser --disabled-password --gecos "" "$U"
fi

UID_T=$(id -u "$U")

# bot Hermes tetap jalan walau user tidak login
loginctl enable-linger "$U"

# batas resource: 1 GB RAM, 1 core CPU
systemctl set-property "user-${UID_T}.slice" MemoryMax=1G CPUQuota=100%

# privasi: orang lain tidak bisa listing home ngemis, tapi nginx tetap bisa traverse
chmod 751 /home/ngemis
chmod 700 "/home/$U"
chmod 700 /home/ngemis/.ssh 2>/dev/null || true

# wrapper supaya teman bisa restart 9router-nya sendiri tanpa akses docker
cat > /usr/local/bin/9router-teman-restart <<'EOF'
#!/bin/sh
exec /usr/bin/docker restart 9router-teman
EOF
chmod 755 /usr/local/bin/9router-teman-restart
echo "$U ALL=(root) NOPASSWD: /usr/local/bin/9router-teman-restart" > "/etc/sudoers.d/9router-$U"
chmod 440 "/etc/sudoers.d/9router-$U"
visudo -cf "/etc/sudoers.d/9router-$U"

echo "SELESAI. user=$U uid=$UID_T"
echo "Langkah berikut: bash 02-9router-teman.sh $U"
