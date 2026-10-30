# ngemis-ai — Infra & Runbook

Konfigurasi host `ngemis-ai` (Ubuntu 24.04, LORD G4x / Core 2 Duo E6400, RAM 4 GB, SSD 240 GB + HDD 1 TB)
supaya server bisa dibangun ulang dari nol tanpa menebak-nebak.

Aplikasi ada di repo terpisah:
- [`print-server`](https://github.com/fikrudzulfahmi/print-server) — CUPS + JetDirect 9100/9101
- [`server-monitor`](https://github.com/fikrudzulfahmi/server-monitor) — dashboard metrik + panel printer
- [`cctv-nvr`](https://github.com/fikrudzulfahmi/cctv-nvr) — NVR EZVIZ (live + rekaman)

## Isi repo
```
nginx/            konfigurasi vhost (cms-tsm :80, cms-tkr :8082, default)
systemd/system/   print9100/9101 socket, cloudflared
systemd/user/     nvr, server-monitor, sigap-banser
sudoers/          aturan NOPASSWD (template + penjelasan)
provisioning/     skrip siapkan user/9router/hermes untuk orang lain
ops/              skrip update SIGAP BANSER (pull, composer, restart)
scripts/          backup-before-reinstall.sh
docs/             rencana migrasi & catatan
```

## Backup SEBELUM instal ulang
```bash
sudo bash scripts/backup-before-reinstall.sh
# hasil: /var/backups/ngemis-ai-<tanggal>.tar.gz  (+ salin ke PC)
```
Isi backup: mysqldump semua database, `.env` tiap proyek, users.json/cameras.json CCTV,
konfigurasi nginx/systemd/sudoers/cups, token Cloudflare, fstab, daftar paket & service.

## Urutan bangun ulang host
1. Install Ubuntu 24.04, user `ngemis`, SSH.
2. Paket dasar:
   ```bash
   sudo apt update && sudo apt install -y nginx php8.4-fpm php8.4-mysql mysql-server \
        docker.io docker-compose-v2 cups cups-client git curl ffmpeg smartmontools
   curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up
   ```
3. **HDD rekaman** (kalau disk baru/ kosong): `sudo bash cctv-nvr/siapkan-hdd.sh`
   (format ext4 + fstab `nofail`). Kalau disk lama dipakai lagi: cukup pasang fstab dengan UUID yang benar.
4. **Docker apps**:
   ```bash
   git clone https://github.com/fikrudzulfahmi/cctv-nvr && cd cctv-nvr && cp .env.example data/.env && docker compose up -d --build
   git clone https://github.com/fikrudzulfahmi/server-monitor && cd server-monitor && cp .env.example data/.env && docker compose up -d --build
   git clone https://github.com/fikrudzulfahmi/print-server && cd print-server && cp .env.example data/.env && docker compose up -d --build
   ```
5. **Cloudflare Tunnel**: `cloudflared service install <TOKEN>` lalu salin pemetaan hostname:
   `cms-tsm`, `cms-tkr`, `sigap`, `cctv`, `engine`, `router` → `http://127.0.0.1:<port>`.
6. **nginx + PHP**: salin `nginx/*.conf` ke `/etc/nginx/sites-available/`, symlink ke `sites-enabled`, `nginx -t && systemctl reload nginx`.
7. **9router**: `docker run -d --name 9router --restart unless-stopped -p 127.0.0.1:20128:20128 -v /opt/9router/data:/app/data -e INITIAL_PASS=... decolua/9router:latest`
8. **Hermes**: install ulang, restore `~/.hermes` dari backup (skills, config, cron).
9. Verifikasi: lihat bagian **Checklist verifikasi**.

## Checklist verifikasi setelah restore
- [ ] `curl -I http://127.0.0.1:8095/` → 302 (NVR hidup)
- [ ] rekaman baru muncul: `ls -lt /mnt/cctv/cam1/$(date +%F) | head`
- [ ] `curl -I http://127.0.0.1:8090/` → 303 (monitor hidup, login)
- [ ] dashboard menampilkan disk `/mnt/cctv` dan proses host
- [ ] `lpstat -t` → dua antrian `EpsonL120` + `EpsonL120-PS`, tes cetak dari Windows
- [ ] `https://cms-tsm.almuhsinblitar.my.id` dan `https://cms-tkr.almuhsinblitar.my.id` → 200
- [ ] `tailscale status` → node online
- [ ] `mysql -e "SHOW DATABASES"` → `cms_tsm` ada

## Catatan penting
- **IP LAN berubah-ubah (DHCP)**: tercatat `.231`, `.232` dalam satu hari. Set DHCP reservation
  di router, atau set static, karena client print `.bat` memakai alamat ini di mode Docker.
- **Tombol shutdown** dashboard nonaktif (`MON_POWER_ENABLED=0`) di Docker; di host bisa
  diaktifkan dengan rule sudoers `systemctl` (lihat `sudoers/`).
- **Nama NetBIOS `NGEMIS-AI`** hanya ada di mode CUPS-host (nmbd). Di Docker, client pakai IP.
- **ffmpeg** ada di image NVR (`/usr/bin/ffmpeg`); di host lama dipakai binary dari `~/.hermes/tools`.
