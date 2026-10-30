# Panduan Instalasi Server `ngemis-ai`

Panduan ini memasang ulang seluruh layanan server dari nol (OS kosong) memakai empat repo:

| Repo | Isi | Port |
|---|---|---|
| `print-server` | CUPS + printer Epson L120 (USB), listener RAW 9100/9101 | 631, 9100, 9101 |
| `server-monitor` | Dashboard metrik + panel printer + tombol daya | 8090 |
| `cctv-nvr` | NVR 6 kamera EZVIZ: live HLS + rekaman 10 menit | 8095 |
| `ngemis-ai-infra` | nginx, systemd, sudoers, cloudflared, 9router, provisioning | 80, 8082, 20128 |

**Urutan wajib:** print-server → server-monitor → cctv-nvr → ngemis-ai-infra.
Alasannya: repo `server-monitor` memakai volume Docker `cups_log` yang dibuat oleh `print-server`,
dan `cctv-nvr` butuh HDD sudah ter-mount.

Perkiraan waktu: 60–90 menit (paling lama: `docker build` + unduh dependency Laravel).

---

## 0. Spesifikasi & asumsi

- Host: PC x86_64 LGA775, RAM 4 GB, SSD 240 GB (sistem) + HDD 1 TB (rekaman).
- OS: Ubuntu Server 24.04 LTS, hostname `ngemis-ai`, user `ngemis` (uid 1000).
- Jaringan: IP LAN statis disarankan (mis. `192.168.1.50`), kamera di `192.168.1.11`–`.16`.
- Semua perintah di bawah dijalankan sebagai `ngemis`, kecuali yang diawali `sudo`.

> **RAM 4 GB**: NVR dibatasi 800 MB, monitor 128 MB. Jangan menjalankan build image
> bersamaan dengan Laravel `composer install` — bisa OOM.

---

## 1. Sistem dasar

```bash
sudo apt update && sudo apt -y full-upgrade
sudo apt -y install git curl ca-certificates htop tmux unzip ufw
sudo timedatectl set-timezone Asia/Jakarta
hostnamectl set-hostname ngemis-ai
```

Buat user (kalau belum ada):

```bash
sudo adduser --uid 1000 ngemis          # lewati kalau user sudah ada
sudo usermod -aG sudo ngemis
```

SSH: nonaktifkan login root dan password (pakai kunci):

```bash
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

Pasang kunci SSH dari komputer Windows kamu *sebelum* mematikan login password.

---

## 2. HDD rekaman di `/mnt/cctv`

HDD 1 TB harus ter-mount **sebelum** NVR dinyalakan; kalau tidak, rekaman masuk ke SSD.

```bash
lsblk -o NAME,SIZE,MODEL,FSTYPE,MOUNTPOINT      # cari disk 1 TB, mis. /dev/sda
sudo mkfs.ext4 -L cctv /dev/sda1                # HANYA kalau disk benar-benar kosong
sudo mkdir -p /mnt/cctv
```

Tambahkan ke `/etc/fstab` (pakai label supaya tahan perubahan urutan disk):

```
LABEL=cctv  /mnt/cctv  ext4  defaults,noatime  0  2
```

```bash
sudo mount -a && df -h /mnt/cctv        # harus muncul ~931G
```

Kalau HDD sudah berisi rekaman lama, **jangan** diformat — cukup mount.
Script bantu ada di repo: `cctv-nvr/siapkan-hdd.sh`.

---

## 3. Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker ngemis
newgrp docker            # atau logout/login
docker version && docker compose version
```

Batasi supaya log container tidak memenuhi SSD (sudah diatur per-compose, ini jaring pengaman):

```bash
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
sudo systemctl restart docker
```

Ambil keempat repo:

```bash
cd ~
for r in print-server server-monitor cctv-nvr ngemis-ai-infra; do
  git clone https://github.com/fikrudzulfahmi/$r.git
done
```

---

## 4. Repo 1 — `print-server`

### 4.1 Konfigurasi

```bash
cd ~/print-server
mkdir -p data
cp .env.example data/.env
nano data/.env
```

Isi `.env`:

```
QUEUE_RAW=EpsonL120
QUEUE_PS=EpsonL120-PS
DEFAULT_QUEUE=EpsonL120
PRINTER_URI=
SERVER_NAME=NGEMIS-AI
```

`PRINTER_URI` dikosongkan = container mencari sendiri lewat `lpinfo -v`
(hasilya `usb://EPSON/L120%20Series...`). Isi manual hanya kalau autodetect gagal.

### 4.2 Jalankan

Colok printer USB lebih dulu, lalu:

```bash
docker compose up -d --build
docker logs -f print-server
```

Log yang benar:

```
[print] menyalakan cupsd
scheduler is running
[print] URI: usb://EPSON/L120%20Series
[print] PPD: gutenprint.5.3://escp2-l120/expert
printer EpsonL120 is idle.  enabled since ...
printer EpsonL120-PS is idle.  enabled since ...
[print] port 9100 -> EpsonL120
[print] port 9101 -> EpsonL120-PS
[print] siap. panel: http://<ip>:631
```

Kalau muncul `percobaan 1/20: printer USB belum terdeteksi`, kabel/power printer belum siap —
colok lalu `docker compose restart`.

### 4.3 Verifikasi

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:631/     # 200
docker exec print-server lpstat -r                                  # scheduler is running
docker exec print-server lpstat -a                                  # 2 antrian accepting
printf 'tes\n' | nc -w2 127.0.0.1 9100 && echo "RAW 9100 OK"
```

---

## 5. Repo 2 — `server-monitor`

### 5.1 Konfigurasi

```bash
cd ~/server-monitor
mkdir -p data
cp .env.example data/.env
nano data/.env
```

```
MON_HOST=0.0.0.0
MON_PORT=8090
MON_USER=admin
MON_PASS=<password panel>
MON_WIDGET_TOKEN=<string acak 24+ byte>
MON_POWER_ENABLED=0
```

`MON_POWER_ENABLED=0` = tombol ⏻ disembunyikan. Aktifkan (`1`) hanya setelah sudoers
dipasang di langkah 7.4.

### 5.2 Jalankan

```bash
docker compose up -d --build
docker logs -f server-monitor
```

Container ini butuh: `pid: host`, mount `/proc`, `/sys`, `/` (read-only), dan volume
`cups_log`. Semua sudah ada di compose — jangan dihapus, kalau tidak metrik jadi milik container.

### 5.3 Verifikasi

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8090/      # 303 -> login
J=/tmp/jar; curl -s -c $J -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"<MON_PASS>"}' http://127.0.0.1:8090/login
curl -s -b $J http://127.0.0.1:8090/api/stats | python3 -m json.tool | head -30
```

Yang harus benar di `/api/stats`:

- `disks` berisi **dua** entri: `/` (~8%) dan `/mnt/cctv` (~14%) — kalau hanya satu dan
  mount-nya aneh (mis. `/etc/hostname`), berarti `MOUNTS_FILE` tidak terpasang.
- `procs` > 50 (proses host, bukan container).
- `print` berisi antrian `EpsonL120` (butuh repo 1 sudah jalan).

---

## 6. Repo 3 — `cctv-nvr`

### 6.1 Konfigurasi

```bash
cd ~/cctv-nvr
mkdir -p data /mnt/cctv
cp .env.example data/.env
cp cameras.json data/cameras.json
nano data/.env
nano data/cameras.json
```

`.env`:

```
NVR_USER=admin
NVR_PASS=<password panel CCTV>
NVR_PORT=8095
CAM1_PASS=<kode verifikasi 6 huruf>
... CAM6_PASS=<...>
REC_DIR=/mnt/cctv
REC_DAYS=30
REC_MIN_FREE_GB=20
REC_AUDIO=1
```

`cameras.json` berisi IP, nama, dan `pass_key` tiap kamera (6 karakter dari aplikasi EZVIZ).
Contoh struktur ada di file itu — ganti IP sesuai jaringan barumu.

### 6.2 Jalankan

```bash
docker compose up -d --build
docker logs -f nvr
```

Compose memakai `network_mode: host` (wajib: RTSP ke LAN + `ip neigh` untuk lacak MAC kamera),
`mem_limit: 800m`, dan tmpfs `/dev/shm/cctv` 256 MB untuk buffer HLS.

### 6.3 Verifikasi

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8095/     # 302 -> login
sleep 12m   # tunggu segmen pertama
find /mnt/cctv -name '*.mp4' -newermt '-15 min' | wc -l             # harus > 0
docker exec nvr sh -c 'ps aux | grep -c "[f]fmpeg"'                 # ~6
```

Login ke panel, cek **semua 6 kamera** tampil live. Kalau satu kamera hitam, lihat
`docker logs nvr | grep -i camN` — biasanya password EZVIZ salah atau kamera sedang
melayani sesi RTSP lain.

> Kamera EZVIZ membatasi jumlah sesi RTSP. Jangan menjalankan instance NVR kedua
> (mis. untuk uji) terhadap kamera yang sama — rekaman utama bisa terputus.

---

## 7. Repo 4 — `ngemis-ai-infra`

Repo ini mengurus hal yang **tidak** masuk container: nginx, PHP, MySQL, cloudflared,
Tailscale, 9router, dan sudoers.

### 7.1 Paket host

```bash
sudo apt -y install nginx mysql-server
sudo add-apt-repository -y ppa:ondrej/php
sudo apt update && sudo apt -y install php8.4-fpm php8.4-cli php8.4-mysql php8.4-mbstring \
  php8.4-xml php8.4-curl php8.4-zip php8.4-bcmath php8.4-gd
php -v
```

### 7.2 Database

```bash
sudo mysql
```

```sql
CREATE DATABASE cms_tsm CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'cms_tsm'@'localhost' IDENTIFIED BY '<password baru>';
GRANT ALL PRIVILEGES ON cms_tsm.* TO 'cms_tsm'@'localhost';
FLUSH PRIVILEGES;
```

Pulihkan data dari dump sebelum wipe:

```bash
gunzip -c ~/backup/cms_tsm.sql.gz | mysql -u cms_tsm -p cms_tsm
mysql -u cms_tsm -p -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='cms_tsm'"
# harus 52
```

### 7.3 Aplikasi PHP

```bash
cd ~
git clone https://github.com/fikrudzulfahmi/new-cms-tsm.git cms-tsm
git clone https://github.com/fikrudzulfahmi/cms-tkr.git cms-tkr

for d in cms-tsm cms-tkr; do
  cd ~/$d
  cp .env.example .env 2>/dev/null || echo "buat .env manual di $d"
  composer install --no-dev --optimize-autoloader
  php artisan key:generate --force
  php artisan migrate --force
  sudo chown -R www-data:www-data storage bootstrap/cache
  cd ~
done
```

`.env` tiap aplikasi: samakan `APP_URL`, `DB_DATABASE/USERNAME/PASSWORD` dengan langkah 7.2.
Aplikasi `sigap-banser` (repo `Nur-Rokhim/sigap-banser`) opsional, jalan di `127.0.0.1:8088`
lewat unit `systemd/user/sigap-banser.service`.

### 7.4 nginx + sudoers + systemd

```bash
cd ~/ngemis-ai-infra

# nginx
sudo cp nginx/cms-tsm.conf nginx/cms-tkr.conf nginx/default.conf /etc/nginx/sites-available/
sudo ln -sf /etc/nginx/sites-available/cms-tsm.conf   /etc/nginx/sites-enabled/cms-tsm
sudo ln -sf /etc/nginx/sites-available/cms-tkr.conf   /etc/nginx/sites-enabled/cms-tkr
sudo ln -sf /etc/nginx/sites-available/default.conf   /etc/nginx/sites-enabled/default
sudo rm -f /etc/nginx/sites-enabled/default.bak
sudo nginx -t && sudo systemctl reload nginx
```

sudoers (dipakai tombol shutdown & deploy):

```bash
sed 's/<USER>/ngemis/g' sudoers/poweroff.sudoers.example | sudo tee /etc/sudoers.d/poweroff >/dev/null
sudo cp sudoers/print-dashboard.sudoers /etc/sudoers.d/print-dashboard
sudo chmod 440 /etc/sudoers.d/poweroff /etc/sudoers.d/print-dashboard
sudo visudo -c                      # wajib "parsed OK"
sudo -n systemctl show -p Version   # harus keluar tanpa minta password
```

Setelah ini baru set `MON_POWER_ENABLED=1` di `~/server-monitor/data/.env` lalu
`docker compose -f ~/server-monitor/docker-compose.yml up -d`.

### 7.5 9router (opsional)

```bash
cd ~/ngemis-ai-infra
cp .env.example .env
nano .env                            # ROUTER_INITIAL_PASS, ROUTER_JWT_SECRET
sudo mkdir -p /opt/9router/data && sudo chown 1000:1000 /opt/9router/data
docker compose up -d
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:20128/    # 200/302
```

### 7.6 Cloudflare Tunnel

```bash
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" \
  | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update && sudo apt -y install cloudflared
```

Pasang token tunnel (ambil dari dashboard Cloudflare → Zero Trust → Tunnels):

```bash
sudo mkdir -p /etc/cloudflared
sudo tee /etc/cloudflared/token >/dev/null <<< '<TOKEN>'
sudo chmod 600 /etc/cloudflared/token
sudo cp ~/ngemis-ai-infra/systemd/system/cloudflared.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now cloudflared
sudo systemctl status cloudflared --no-pager
```

Public hostname → service yang harus ada di dashboard:

| Hostname | Service lokal |
|---|---|
| `cms-tsm.almuhsinblitar.my.id` | `http://127.0.0.1:80` |
| `cms-tkr.almuhsinblitar.my.id` | `http://127.0.0.1:8082` |
| `cctv.almuhsinblitar.my.id` | `http://127.0.0.1:8095` |
| `engine.almuhsinblitar.my.id` | `http://127.0.0.1:8090` |
| `router.almuhsinblitar.my.id` | `http://127.0.0.1:20128` |

### 7.7 Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh
tailscale status
```

IP tailnet dipakai untuk akses darurat kalau Cloudflare tunnel mati.

### 7.8 Firewall

```bash
sudo ufw allow 22/tcp
sudo ufw allow 8090/tcp     # dashboard
sudo ufw allow 8095/tcp     # NVR
sudo ufw allow 631/tcp
sudo ufw allow 9100:9101/tcp
sudo ufw allow in on tailscale0
sudo ufw enable
```

Port 80/8082/20128 **tidak** dibuka ke internet — hanya lewat tunnel.

---

## 8. Client Windows (printer)

Nama NetBIOS `NGEMIS-AI` hilang karena CUPS sekarang di container, jadi client memakai IP.

1. Jalankan `client/Pasang-Printer-L120.bat` sebagai admin di tiap PC.
2. Saat diminta, isi IP server (`192.168.1.50`) — bukan nama host.
3. Uji: `notepad` → Ctrl+P → pilih `EpsonL120` → cetak.

Kalau driver belum ada: jalankan `client/Ambil-Driver.bat`, atau ambil dari
`client/driver/` (file driver tidak disimpan di repo karena besar/berlisensi).

---

## 9. Verifikasi akhir (checklist)

```bash
docker ps --format '{{.Names}}\t{{.Status}}'      # 4 container Up
systemctl is-active nginx mysql php8.4-fpm cloudflared tailscaled
curl -s -o /dev/null -w 'monitor %{http_code}\n'  http://127.0.0.1:8090/
curl -s -o /dev/null -w 'nvr     %{http_code}\n'  http://127.0.0.1:8095/
curl -s -o /dev/null -w 'cms-tsm %{http_code}\n'  http://127.0.0.1/
find /mnt/cctv -name '*.mp4' -newermt '-15 min' | wc -l
free -h                                            # sisa RAM > 800 MB
df -h / /mnt/cctv
```

Uji dari luar (HP dengan data seluler, bukan Wi-Fi):

- `https://cctv.almuhsinblitar.my.id` → login → semua kamera live
- `https://engine.almuhsinblitar.my.id` → dashboard metrik + panel printer
- `https://cms-tsm.almuhsinblitar.my.id` → aplikasi sekolah

---

## 10. Troubleshooting

| Gejala | Penyebab | Perbaikan |
|---|---|---|
| Panel disk cuma 1 baris / mount aneh | `MOUNTS_FILE` tidak diset | pastikan `MOUNTS_FILE=/host/proc/1/mounts` di compose monitor |
| `docker compose` gagal: `env file ... not found` | `data/.env` belum dibuat | `mkdir -p data && cp .env.example data/.env` |
| CUPS tidak menemukan printer | USB belum ter-map / printer mati | cek `devices: /dev/bus/usb`, `docker compose restart` |
| Client Windows gagal cetak | pakai nama `NGEMIS-AI` | ganti ke IP server |
| Rekaman tidak muncul | `/mnt/cctv` tidak ter-mount | `mount -a`, restart container `nvr` |
| NVR mati tiap beberapa jam | RAM habis (OOM) | cek `dmesg | grep -i oom`; naikkan `mem_limit` bila RAM lega |
| Kamera hitam 1–2 buah | sesi RTSP bentrok / password salah | matikan instance NVR lain, cek `CAMn_PASS` |
| HLS live patah-patah | `/dev/shm/cctv` penuh | pastikan tmpfs 256 MB aktif, turunkan kualitas kamera |
| Tombol ⏻ tidak muncul | `MON_POWER_ENABLED=0` | set `1` + sudoers NOPASSWD terpasang |
| Shutdown tidak jalan | sudoers belum benar | `sudo visudo -c`, `sudo -n systemctl show -p Version` |
| 502 di domain | service lokal mati | `docker ps`, `systemctl status php8.4-fpm` |

---

## 11. Sebelum wipe (checklist)

1. `~/backup/pre-reinstall-<tanggal>/` sudah berisi: `cms_tsm.sql.gz`, `hermes-skills.tar.gz`,
   `asli-luar-repo.tar.gz` (QR_Per_Kelas, dokumen, bell-server, setup-teman, sigap-banser-watch).
2. Empat repo + `hermes-skills` sudah ter-push ke GitHub (cek `git -C ~/repos/<repo> status`).
3. Token GitHub di `~/.git-credentials` dan remote repo `cms-tsm` **dirotasi** setelah server baru siap.
4. Salin folder `~/backup` ke disk eksternal / Google Drive — jangan hanya bergantung pada SSD lama.
5. Catat: token Cloudflare Tunnel, kode verifikasi 6 kamera EZVIZ, password MySQL baru,
   password panel monitor & NVR.

Setelah salinan aman, instal ulang dan ikuti panduan ini dari langkah 1.
