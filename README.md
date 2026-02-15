# Auto-Install Django + MySQL + Nginx (Debian/Ubuntu)

![Banner](https://raw.githubusercontent.com/wiratmoko1708/auto-install-django-mysql-nginx/main/assets/banner.png)

Script bash ini dirancang untuk mengotomatiskan seluruh proses instalasi server untuk aplikasi Django pada sistem operasi Debian 12 atau Ubuntu 20.04+. Script ini menangani segalanya mulai dari update sistem hingga konfigurasi SSL.

## 🚀 Fitur Utama

- **Update & Upgrade Sistem** secara otomatis.
- **Instalasi Paket Dasar**: git, curl, certbot, build-essential, dll.
- **Konfigurasi Firewall (UFW)**: Membuka port SSH, HTTP, HTTPS, dan MySQL.
- **MariaDB (MySQL) Setup**: Instalasi dan pengamanan database secara otomatis.
- **Nginx & Gunicorn**: Konfigurasi otomatis sebagai reverse proxy dan daemon service.
- **Python Virtualenv**: Isolasi environment untuk setiap proyek.
- **SSL Otomatis**: Integrasi dengan Let's Encrypt (Certbot).
- **Security Fixes**: Penanganan otomatis untuk CSRF trusted origins, session cookies, dan static files permissions.

## 🛠️ Alur Kerja

![Workflow](https://raw.githubusercontent.com/wiratmoko1708/auto-install-django-mysql-nginx/main/assets/steps.png)

1. **Persiapan Server**: Memastikan semua dependensi sistem terpenuhi.
2. **Konfigurasi Otomatis**: Mengatur database, virtual environment, dan config files Django.
3. **Siap Deploy**: Website Anda langsung aktif dan dapat diakses via domain.

## 📖 Cara Penggunaan

### 1. Unduh Script
```bash
wget https://raw.githubusercontent.com/wiratmoko1708/auto-install-django-mysql-nginx/main/auto-django-ok.sh
chmod +x auto-django-ok.sh
```

### 2. Jalankan Script
Pastikan Anda menjalankan script ini sebagai **root** atau dengan **sudo**:
```bash
sudo ./auto-django-ok.sh
```

### 3. Masukkan Informasi yang Diminta
Script akan meminta beberapa input selama proses:
- Password root MySQL baru.
- Nama domain (contoh: `example.com`).
- Nama proyek Django.
- Kredensial database (nama DB, user, dan password).

## 📂 Struktur Direktori
Setelah instalasi, proyek Anda akan berada di:
- **Project Root**: `/var/www/domain-anda.com/`
- **Virtualenv**: `/var/www/domain-anda.com/venv/`
- **Nginx Config**: `/etc/nginx/sites-available/domain-anda.com`

## ⚖️ Lisensi
Proyek ini dilisensikan di bawah [MIT License](LICENSE).

---
*Dibuat dengan ❤️ oleh [wiratmoko1708](https://github.com/wiratmoko1708)*
