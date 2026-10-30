# Rencana: Reinstall ngemis-ai + Repo GitHub + Dockerisasi

Status: **DRAF — belum dieksekusi**. Tanggal survei: 30 Okt 2026.
Server: LORD G4x 775 / Intel Core 2 Duo E6400 / RAM 4 GB / SSD 240 GB + HDD 1 TB / Ubuntu 24.04.5.

---

## 1. Ringkasan temuan

| Proyek | Lokasi | Ukuran | Repo | Kondisi |
|---|---|---|---|---|
| Print server | `~/printserver` | 44 KB | **belum ada** | 5 file (setup + client Windows) |
| Server monitor | `~/server-monitor` | 176 KB | **belum ada** | 11 file + `.env` rahasia |
| NVR CCTV | `~/cctv` | 516 KB | **belum ada** | 17 file, sebagian runtime/rahasia |

Akun GitHub `fikrudzulfahmi`: 26 repo. Tidak ada satu pun bernama print-server / server-monitor / cctv / nvr.

Catatan keamanan yang ditemukan:
- `~/cms-tsm/.git/config` menyimpan PAT di URL remote (`https://fikrudzulfahmi:ghp_***@github.com/...`). Token ikut terbaca siapa pun yang bisa baca folder. **Perlu diganti + remote dibersihkan** sebelum/sesudah reinstall.
- `.env` semua proyek tidak ter-track di git (bagus), tapi belum ada `.env.example` sebagai dokumentasi variabel.

---

## 2. Tiga repo baru

Semua **private** dulu (bisa dibuka publik nanti), owner `fikrudzulfahmi`.

### 2.1 `print-server`
Isi:
```
README.md
setup-server.sh              # provisioning CUPS + queue RAW/PS + port 9100/9101 + nmbd
client/Pasang-Printer-L120.bat
client/Ambil-Driver.bat
client/driver/BACA.txt
docker/Dockerfile            # CUPS dalam container
docker/cupsd.conf
docker-compose.yml
.env.example                 # PRINTER_NAME, PRINTER_URI, SERVER_NAME
.gitignore
```
Jangan di-commit: `Printer-L120-Client.zip` (hasil build, taruh di Releases), driver Windows binary.

### 2.2 `server-monitor`
Isi:
```
README.md
monitor.py
index.html
login.html
manifest.json
sw.js
icon-192.png, icon-512.png
setup-print-control.sh       # sudoers NOPASSWD cupsenable/cupsdisable/cancel
Dockerfile
docker-compose.yml
.env.example                 # MON_HOST, MON_PORT, MON_USER, MON_PASS, MON_WIDGET_TOKEN,
                             # MON_POWER_PASS, MON_POWER_DELAY
.gitignore                   # .env, __pycache__/
```
`monitor.py` murni stdlib; dependensi eksternal: `lpstat`/`lpadmin` (CUPS), `/snap/bin/speedtest` (opsional), `sudo systemctl` (tombol shutdown).

### 2.3 `cctv-nvr`
Isi:
```
README.md
nvr.py
index.html
login.html
cameras.json                 # AMAN: hanya nama key (CAM1_PASS), bukan password
static/hls.min.js
siapkan-hdd.sh               # format + mount HDD rekaman (ada safety check)
test_cams.py, test_nvr.py
Dockerfile
docker-compose.yml
.env.example                 # CAM1..6_PASS, NVR_USER, NVR_PASS, NVR_PORT,
                             # REC_DIR, REC_DAYS, REC_MIN_FREE_GB, REC_AUDIO
.gitignore                   # .env, .secret, users.json, rec-*.log, __pycache__/
```
`nvr.py` membuat `.secret` dan `users.json` otomatis dari `NVR_USER`/`NVR_PASS` → aman tidak di-commit.

---

## 3. Rencana Docker

### 3.1 NVR (paling mudah)
```yaml
services:
  nvr:
    build: .
    network_mode: host          # wajib: RTSP ke LAN + `ip neigh` untuk lacak MAC/IP kamera
    volumes:
      - /mnt/cctv:/mnt/cctv     # rekaman
      - ./config:/config        # .env + cameras.json
      - type: tmpfs             # pengganti /dev/shm/cctv
        target: /dev/shm/cctv
        tmpfs: { size: 268435456 }
    restart: unless-stopped
    mem_limit: 800m
    cpus: 1.2
```
- Image: `python:3.12-slim` + `apt-get install -y ffmpeg iproute2`.
- **Penting:** `nvr.py` meng-hardcode `FFMPEG=/home/ngemis/.hermes/tools/ffmpeg-.../bin/ffmpeg`. Di container wajib diubah jadi `os.environ.get("FFMPEG","/usr/bin/ffmpeg")` — kalau tidak, container mati total.
- `HLS_DIR` jadi env (`HLS_DIR`, default `/dev/shm/cctv`).

### 3.2 Server monitor (butuh akses host)
```yaml
services:
  monitor:
    build: .
    network_mode: host
    pid: host                  # agar /proc menampilkan proses host
    volumes:
      - /proc:/host/proc:ro
      - /sys:/sys:ro
      - /etc/os-release:/etc/os-release:ro
      - /var/log/cups:/var/log/cups:ro
      - /run/cups/cups.sock:/run/cups/cups.sock
      - /var/run/docker.sock:/var/run/docker.sock   # untuk tombol shutdown
    restart: unless-stopped
```
Perlu penyesuaian kode: pembacaan `/proc` dan `/sys` dibuat lewat prefix env (`PROC_ROOT`, `SYS_ROOT`).

### 3.3 Print server (paling rumit — perlu keputusan)
CUPS bisa dikontainerkan, tapi tiga hal ini tidak bisa ikut ke dalam container:
1. **USB printer** → `devices: [/dev/bus/usb:/dev/bus/usb]` + `privileged` (bisa, tapi rapuh kalau printer dicabut-pasang).
2. **NetBIOS name `NGEMIS-AI`** (nmbd) → klien Windows `.bat` memanggil `\\NGEMIS-AI`. nmbd di container butuh `network_mode: host` + port 137-138; sering bentrok.
3. **LLMNR** (`/etc/systemd/resolved.conf.d/llmnr.conf`) → level host, tidak bisa dikontainerkan.

Dua opsi:
- **Opsi A (rekomendasi):** CUPS tetap di host (`setup-server.sh` sudah otomatis + idempoten). Container hanya untuk aplikasi yang memang stateless. Reinstall tetap cepat: satu script.
- **Opsi B:** CUPS di container dengan `network_mode: host` + `--device /dev/bus/usb` + `avahi` di dalam. Nama `NGEMIS-AI` diganti IP statis; klien `.bat` diubah pakai IP/hostname DNS. Kelebihan: benar-benar portable. Kekurangan: print via USB di container paling sering jadi sumber masalah.

---

## 4. Yang WAJIB di-backup sebelum wipe

### 4.1 Data & rahasia aplikasi
- [ ] `mysqldump` database `cms_tsm` + daftar user/grant MySQL.
- [ ] Semua `.env`: `cms-tsm`, `cms-tkr`, `siber`, `au-backend`, `wa-gateway`, `sigap-banser`, `cctv`, `server-monitor`.
- [ ] `~/cctv/cameras.json`, `~/cctv/users.json` (atau cukup `.env` — users.json bisa dibuat ulang).
- [ ] Token Cloudflare `/etc/cloudflared/token` + daftar public hostname:
      cctv, cms-tkr, cms-tsm, engine, router, sigap `.almuhsinblitar.my.id`.
- [ ] Identitas Tailscale (atau siapkan auth key baru; node `ngemis-ai` 100.112.217.63).
- [ ] 9router: `/opt/9router/data` + `docker inspect` env (`INITIAL_PASS`, `JWT_SECRET`).
- [ ] `~/.hermes` (skills 85 file/5.2 MB, config.yaml, `.gh_token`, cron) — jangan campur token ke repo publik.

### 4.2 Konfigurasi sistem (belum ada di repo mana pun → masuk repo infra)
- nginx: `sites-available/{cms-tsm,cms-tkr,default}` + php8.4-fpm pool.
- systemd: `print9100.socket`, `print9100@.service`, `print9101.socket`, `print9101@.service`, `cloudflared.service`.
- systemd user: `nvr.service`, `server-monitor.service`, `sigap-banser.service`, `hermes-gateway.service`.
- sudoers: `/etc/sudoers.d/ngemis-deploy`, `/etc/sudoers.d/print-dashboard`, rule `NOPASSWD: /usr/bin/systemctl`.
- CUPS: `cupsd.conf` (baris `ServerAlias *`), `printers.conf`, `cups-files.conf`.
- fstab: `UUID=2f6f2ba3-... /mnt/cctv ext4 defaults,noatime,nofail 0 2`.
- `resolved.conf.d/llmnr.conf`, `smb.conf` (netbios NGEMIS-AI).
- Paket manual: cups, printer-driver-escpr, samba, avahi, mysql-server, nginx, php8.4-fpm, docker, cloudflared, tailscale, smartmontools.

---

## 5. Temuan lain yang belum masuk repo

| Item | Isi | Saran |
|---|---|---|
| `~/bell-server` | repo `bell-sekolah` sudah ada, **1 file dirty** (`install.sh`) | commit + push sebelum wipe |
| `~/bell-sekolah/` | `index.html` lama, tanpa git, duplikat versi di `bell-server` | arsipkan/hapus |
| `~/sigap-banser-watch` | `update.sh`, `run.sh`, patch, log | repo baru `sigap-deploy` (repo `sigap-banser` milik org lain) |
| `~/setup-teman` | 3 script provisioning user/9router/hermes | gabung ke repo `ngemis-ai-infra` |
| `~/QR_Per_Kelas` | 944 file, 3.9 MB (24 kelas QR) | data hasil generate → repo private `qr-per-kelas` atau zip di Drive |
| `~/dokumen` | 2 dokumen sekolah (docx/xlsx) | Drive, bukan git |
| `~/backup`, `~/backups` | 2 dump JSON | data, jangan git |
| `~/mysql-uji` | kosong | hapus |
| Konfigurasi sistem (§4.2) | nginx, systemd, sudoers, cups, fstab | **repo `ngemis-ai-infra`** — inti reproducibility reinstall |
| `~/.hermes/skills` | 85 skill | repo private `hermes-skills` (tanpa token/session) |
| 9router | image `decolua/9router:latest` + `/opt/9router/data` | masuk `ngemis-ai-infra/docker-compose.yml` |

---

## 6. Struktur repo yang disarankan

**Opsi 1 (rekomendasi): 4 repo**
```
print-server        # app + client Windows + Dockerfile
server-monitor      # app + Dockerfile
cctv-nvr            # app + Dockerfile
ngemis-ai-infra     # docker-compose semua service, nginx/, systemd/, sudoers/,
                    # cloudflared/, provisioning/, README reinstall runbook
```
Alasan: tiap app bisa di-deploy ulang sendiri; infra punya siklus hidup berbeda.

**Opsi 2: 1 monorepo `homelab`** dengan `apps/{print,monitor,nvr}` + `infra/`. Lebih ringkas, tapi push kecil-kecilan ikut menyeret riwayat semua app.

---

## 7. Urutan eksekusi (setelah disetujui)

1. Backup penuh (§4) ke folder aman + unduh ke PC Windows.
2. Commit/push `bell-server` yang dirty.
3. Buat 3 repo app + 1 repo infra; tambah `.env.example`, `.gitignore`, README; **tanpa** rahasia.
4. Ubah kode agar container-ready: `FFMPEG`/`HLS_DIR`/`PROC_ROOT` jadi env.
5. Tulis Dockerfile + compose; uji `docker compose up` di server **sebelum** reinstall (paralel: port 8095 → 8096, 8090 → 8091) supaya bisa dibandingkan dengan versi systemd.
6. Verifikasi: rekaman baru muncul di `/mnt/cctv`, dashboard menampilkan data host, print test page.
7. Baru reinstall OS; restore dari repo + backup.
8. Ganti PAT GitHub yang bocor di remote `cms-tsm`.

---

## 8. Pertanyaan terbuka (perlu keputusan)

1. **Repo:** 4 repo terpisah (rekomendasi) atau 1 monorepo `homelab`?
2. **Visibilitas:** semua private (rekomendasi) atau `print-server` publik?
3. **CUPS:** tetap di host (Opsi A, rekomendasi) atau masuk container (Opsi B, nama NGEMIS-AI hilang)?
4. **Tombol shutdown** setelah Docker: tetap bisa matikan host (perlu docker socket + `nsenter`) atau cukup restart container NVR saja?
5. **Repo infra** ikut menyimpan `~/.hermes/skills` + config (tanpa token), atau dipisah?
6. **OS reinstall:** Ubuntu 24.04 LTS lagi (stabil, semua script sudah cocok) atau naik ke 26.04?
