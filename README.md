# n8n-automation-infra

n8n + Postgres/pgvector self-hosted di VPS Oracle Cloud Always Free, memakai Docker Compose.
Menggantikan instance n8n di Sumopod supaya workflow, credential, dan data privat (riwayat lamaran,
draf CV, index knowledge) tidak disimpan di server pihak ketiga.

Asal-usul: wizard ini dipindah dari `my-profile/docs/infra/oracle-n8n/` (tiket `job-automation` 01/02).

## Isi repo

| Path                        | Fungsi                                                                      |
| --------------------------- | --------------------------------------------------------------------------- |
| `stack/docker-compose.yml`  | n8n `2.47.7` + `pgvector/pgvector:0.8.1-pg17`, port hanya di `127.0.0.1`    |
| `stack/init/01-knowledge.sql` | Membuat DB `knowledge` + extension `vector` (hanya saat volume masih kosong) |
| `stack/backup.sh`           | `pg_dumpall` harian ke `~/backups` di server, simpan 7 hari                 |
| `scripts/setup-oracle.sh`   | Wizard 9 tahap: akun Oracle → Pay-As-You-Go + budget → VM A1 → Docker → deploy → backup key → tunnel              |
| `scripts/setup-domain.sh`  | Wizard domain publik: DNS ke Cloudflare → Tunnel → Access → deploy         |
| `scripts/deploy.sh`         | Upload `stack/` ke `~/n8n` di server lalu `docker compose up -d`            |
| `.env.example`              | Daftar secret yang dibutuhkan; nilai asli tidak pernah masuk repo           |

## Setup pertama

```bash
bash scripts/setup-oracle.sh
```

Wizard membuka console Oracle di browser, menjelaskan apa yang harus diklik, dan menyimpan nilai
(region, IP, SSH key, `POSTGRES_PASSWORD`, `N8N_ENCRYPTION_KEY`) ke `~/.config/oracle-n8n/.env`
(mode 600, di luar repo). Bisa dihentikan dengan Ctrl-C dan dijalankan ulang.

Kebutuhan lokal: `ssh`, `scp`, `ssh-keygen`, `openssl`, browser (di WSL lewat `wslview`).
Docker **tidak** perlu di mesin lokal; Docker hanya jalan di server.

## Update stack

Ubah file di `stack/` (misalnya tag image n8n), commit, lalu:

```bash
bash scripts/deploy.sh
```

Script menolak jalan bila `N8N_ENCRYPTION_KEY` di server berbeda dengan yang lokal, supaya
credential n8n tidak rusak.

## Pemakaian sehari-hari

```bash
# tunnel: 5678 = n8n, 5432 = Postgres knowledge (untuk skrip ingest)
ssh -N -L 5678:localhost:5678 -L 5432:localhost:5432 oracle-n8n
# lalu buka http://localhost:5678

ssh oracle-n8n 'cd ~/n8n && docker compose ps && docker compose logs --tail 50 n8n'

# ambil backup terbaru ke lokal
scp "oracle-n8n:backups/$(ssh oracle-n8n 'ls -t ~/backups | head -1')" .
```

## Domain publik (Cloudflare Tunnel)

```bash
bash scripts/setup-domain.sh
```

Wizard memindah DNS domain dari Hostinger ke Cloudflare, membuat Tunnel ke container `n8n`, dan
memasang Cloudflare Access. Hasilnya:

- `https://<N8N_DOMAIN>/`: editor n8n, harus lolos kode OTP email Access dulu, baru login n8n.
- `https://<N8N_DOMAIN>/webhook/*` dan `/webhook-test/*`: bypass Access supaya layanan luar bisa
  memanggil. Setiap Webhook node wajib memakai Header Auth.
- VPS tetap tidak membuka port; `cloudflared` hanya membuat koneksi keluar.
- Tunnel SSH ke `localhost:5678` tetap jalan sebagai cadangan.

`deploy.sh` menyalakan service `cloudflared` (profile `tunnel`) dan mengisi `N8N_HOST`,
`N8N_PROTOCOL`, `N8N_EDITOR_BASE_URL`, `N8N_WEBHOOK_URL`, `N8N_PROXY_HOPS` hanya bila
`N8N_DOMAIN` dan `CLOUDFLARE_TUNNEL_TOKEN` ada di `~/.config/oracle-n8n/.env`.

Konsekuensi privasi: Cloudflare membuka TLS di edge-nya, jadi isi request lewat Cloudflare.
Data tetap tersimpan hanya di VPS.

## Sumopod

Per 2026-11-15 belum ada workflow di instance Sumopod, jadi tidak ada yang perlu dimigrasi.
Workflow baru dibuat langsung di n8n Oracle.

## Hal penting

- **Backup `N8N_ENCRYPTION_KEY`** ke password manager (wizard tahap 8, entri `oracle-n8n`). Wizard
  meminta key ditempel balik dari password manager untuk memastikan tersimpan utuh. Tanpa key ini,
  credential n8n tidak bisa dipulihkan dari backup database.
- Backup harian hanya ada di disk VPS yang sama. Tarik ke lokal secara berkala (perintah `scp` di atas).
- **Akun Pay-As-You-Go, bukan Free Tier** (keputusan 2026-11-15). Di akun Free Tier, VM Always Free
  yang menganggur (CPU, network, dan memory di bawah 20% p95 selama 7 hari) bisa diambil Oracle
  beserta disknya. Akun PAYG tidak terkena aturan itu, dan resource Always Free tetap gratis.
  Wizard tahap 2 memandu upgrade dan budget alert `monthly-guard` ($1/bulan, email di 50% aktual
  dan 100% forecast). Budget alert hanya memberi tahu, tidak menghentikan biaya: buat hanya
  resource berlabel "Always Free-eligible".
- Batas Always Free A1 sekarang 2 OCPU / 12 GB; disk boot + block total 200 GB.
- "Out of host capacity" saat membuat instance itu umum: coba availability domain lain atau ulangi nanti.
- Tidak ada port publik selain SSH. Kalau butuh webhook masuk, pakai Cloudflare Tunnel, jangan buka
  port di security list.

## Sumber

- [Oracle Always Free Resources](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [Oracle: network traffic di image Ubuntu](https://blogs.oracle.com/developers/post/enabling-network-traffic-to-ubuntu-images-in-oracle-cloud-infrastructure)
- [n8n: Docker Compose + Postgres](https://github.com/n8n-io/n8n-docs/blob/main/docs/deploy/host-n8n/install-options/install-using-docker-compose.md)
