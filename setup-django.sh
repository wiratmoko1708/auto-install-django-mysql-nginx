#!/bin/bash

# ==========================================
# Django + Nginx + MySQL Auto Install Script
# Supports: Debian 12 / Ubuntu 20.04+
# ==========================================

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==========================================
# Helper Functions
# ==========================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Script ini harus dijalankan sebagai root (sudo)."
        exit 1
    fi
}

check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        log_error "Sistem operasi tidak didukung atau tidak terdeteksi."
        exit 1
    fi

    log_info "Terdeteksi OS: $OS $VER"
}

# ==========================================
# 1. Update Sistem
# ==========================================
step_update_system() {
    log_info "1. Update Sistem..."
    apt update && apt upgrade -y
    log_success "Sistem berhasil diupdate."
}

# ==========================================
# 2. Instalasi Paket Dasar
# ==========================================
step_install_basics() {
    log_info "2. Instalasi Paket Dasar..."
    apt install -y apt-transport-https ca-certificates \
        certbot curl cron git gnupg lsb-release \
        software-properties-common unzip wget \
        python3 python3-pip python3-venv python3-dev \
        build-essential libmysqlclient-dev pkg-config \
        python3-certbot-nginx
    log_success "Paket dasar terinstall."
}

# ==========================================
# 3 & 4. Konfigurasi Firewall
# ==========================================
step_setup_firewall() {
    log_info "3. Konfigurasi Firewall (UFW)..."
    apt install -y ufw

    ufw allow ssh
    ufw allow http
    ufw allow https
    ufw allow 3306 # MySQL

    # Enable UFW non-interactive
    echo "y" | ufw enable

    log_info "4. Status Firewall:"
    ufw status
}

# ==========================================
# 5. Instalasi MySQL
# ==========================================
step_install_db() {
    log_info "5. Instalasi MySQL / MariaDB..."
    apt install -y mariadb-server mariadb-client libmariadb-dev
    systemctl enable mariadb
    systemctl start mariadb
    log_success "MariaDB terinstall dan berjalan."

    log_info "Menjalankan mysql_secure_installation secara otomatis..."
    # Set root password dan amankan instalasi
    read -sp "Masukkan password root MySQL baru: " MYSQL_ROOT_PASS
    echo ""

    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASS}';" 2>/dev/null || \
    mysql -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${MYSQL_ROOT_PASS}');" 2>/dev/null

    mysql -u root -p"${MYSQL_ROOT_PASS}" <<EOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

    log_success "MySQL telah diamankan."
}

# ==========================================
# 6. Instalasi Nginx
# ==========================================
step_install_nginx() {
    log_info "6. Instalasi Nginx..."
    apt install -y nginx
    systemctl enable nginx
    systemctl start nginx
    log_success "Nginx terinstall dan berjalan."
}

# ==========================================
# 7. Setup Proyek Django
# ==========================================
step_setup_django() {
    log_info "7. Setup Proyek Django..."

    read -p "Masukkan Nama Domain (contoh: example.com): " DOMAIN_NAME
    if [[ -z "$DOMAIN_NAME" ]]; then
        log_error "Domain tidak boleh kosong."
        exit 1
    fi

    read -p "Masukkan nama proyek Django (contoh: myproject): " PROJECT_NAME
    if [[ -z "$PROJECT_NAME" ]]; then
        PROJECT_NAME="myproject"
    fi

    APP_DIR="/var/www/$DOMAIN_NAME"
    mkdir -p "$APP_DIR"

    # Buat virtual environment
    log_info "Membuat virtual environment Python..."
    python3 -m venv "$APP_DIR/venv"
    source "$APP_DIR/venv/bin/activate"

    # Install Django dan dependensi
    log_info "Menginstall Django dan dependensi..."
    pip install --upgrade pip
    pip install django gunicorn mysqlclient

    # Buat proyek Django jika belum ada
    if [ ! -f "$APP_DIR/$PROJECT_NAME/manage.py" ]; then
        log_info "Membuat proyek Django baru: $PROJECT_NAME..."
        django-admin startproject "$PROJECT_NAME" "$APP_DIR/$PROJECT_NAME"
    else
        log_warning "Proyek Django sudah ada, melewati pembuatan proyek."
    fi

    # Setup database MySQL untuk Django
    log_info "Membuat database MySQL untuk Django..."
    read -p "Masukkan nama database (default: ${PROJECT_NAME}_db): " DB_NAME
    DB_NAME=${DB_NAME:-${PROJECT_NAME}_db}

    read -p "Masukkan nama user database (default: ${PROJECT_NAME}_user): " DB_USER
    DB_USER=${DB_USER:-${PROJECT_NAME}_user}

    read -sp "Masukkan password user database: " DB_PASS
    echo ""

    read -sp "Masukkan password root MySQL: " MYSQL_ROOT_PASS
    echo ""

    mysql -u root -p"${MYSQL_ROOT_PASS}" <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

    log_success "Database '${DB_NAME}' dan user '${DB_USER}' berhasil dibuat."

    # Update settings.py untuk MySQL
    SETTINGS_FILE="$APP_DIR/$PROJECT_NAME/$PROJECT_NAME/settings.py"
    if [ -f "$SETTINGS_FILE" ]; then
        log_info "Mengkonfigurasi settings.py untuk MySQL..."

        # Ganti DATABASES config
        python3 <<PYEOF
import re

with open("$SETTINGS_FILE", "r") as f:
    content = f.read()

# Ganti ALLOWED_HOSTS
content = re.sub(
    r"ALLOWED_HOSTS\s*=\s*\[.*?\]",
    "ALLOWED_HOSTS = ['$DOMAIN_NAME', 'www.$DOMAIN_NAME', 'localhost', '127.0.0.1']",
    content,
    flags=re.DOTALL
)

# Ganti DATABASES
old_db = re.compile(r"DATABASES\s*=\s*\{.*?\n\}", re.DOTALL)
new_db = """DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.mysql',
        'NAME': '${DB_NAME}',
        'USER': '${DB_USER}',
        'PASSWORD': '${DB_PASS}',
        'HOST': 'localhost',
        'PORT': '3306',
        'OPTIONS': {
            'charset': 'utf8mb4',
        },
    }
}"""
content = old_db.sub(new_db, content)

# Tambah STATIC_ROOT
if "STATIC_ROOT" not in content:
    content += "\nSTATIC_ROOT = BASE_DIR / 'staticfiles'\n"

with open("$SETTINGS_FILE", "w") as f:
    f.write(content)
PYEOF
        log_success "settings.py berhasil dikonfigurasi."
    fi

    # Jalankan migrate dan collectstatic
    log_info "Menjalankan migrasi database..."
    cd "$APP_DIR/$PROJECT_NAME"
    "$APP_DIR/venv/bin/python" manage.py migrate
    "$APP_DIR/venv/bin/python" manage.py collectstatic --noinput 2>/dev/null || true

    # Set permissions
    chown -R www-data:www-data "$APP_DIR"

    deactivate
    log_success "Proyek Django berhasil disetup."
}

# ==========================================
# 8. Konfigurasi Gunicorn (systemd)
# ==========================================
step_configure_gunicorn() {
    log_info "8. Konfigurasi Gunicorn sebagai systemd service..."

    # Buat socket file
    cat > /etc/systemd/system/gunicorn-$DOMAIN_NAME.socket <<EOF
[Unit]
Description=Gunicorn Socket untuk $DOMAIN_NAME

[Socket]
ListenStream=/run/gunicorn-$DOMAIN_NAME.sock

[Install]
WantedBy=sockets.target
EOF

    # Buat service file
    cat > /etc/systemd/system/gunicorn-$DOMAIN_NAME.service <<EOF
[Unit]
Description=Gunicorn Daemon untuk $DOMAIN_NAME
Requires=gunicorn-$DOMAIN_NAME.socket
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=$APP_DIR/$PROJECT_NAME
ExecStart=$APP_DIR/venv/bin/gunicorn \\
    --access-logfile - \\
    --workers 3 \\
    --bind unix:/run/gunicorn-$DOMAIN_NAME.sock \\
    $PROJECT_NAME.wsgi:application

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable gunicorn-$DOMAIN_NAME.socket
    systemctl start gunicorn-$DOMAIN_NAME.socket
    systemctl enable gunicorn-$DOMAIN_NAME.service
    systemctl start gunicorn-$DOMAIN_NAME.service

    log_success "Gunicorn service berhasil dikonfigurasi dan dijalankan."
}

# ==========================================
# 9. Konfigurasi Nginx Virtual Host
# ==========================================
step_configure_nginx() {
    log_info "9. Konfigurasi Nginx Virtual Host..."

    cat > /etc/nginx/sites-available/$DOMAIN_NAME <<EOF
server {
    listen 80;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;

    location = /favicon.ico { access_log off; log_not_found off; }

    location /static/ {
        alias $APP_DIR/$PROJECT_NAME/staticfiles/;
    }

    location /media/ {
        alias $APP_DIR/$PROJECT_NAME/media/;
    }

    location / {
        include proxy_params;
        proxy_pass http://unix:/run/gunicorn-$DOMAIN_NAME.sock;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/$DOMAIN_NAME /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    log_info "Testing konfigurasi Nginx..."
    nginx -t && systemctl restart nginx

    log_success "Nginx Virtual Host berhasil dikonfigurasi."
}

# ==========================================
# 10. Setup SSL dengan Certbot
# ==========================================
step_setup_ssl() {
    log_info "10. Setup SSL dengan Certbot..."
    echo "Apakah Anda ingin setup SSL sekarang? (Domain harus sudah pointing ke server ini)"
    read -p "Setup SSL? (y/n): " ssl_choice

    if [[ "$ssl_choice" == "y" || "$ssl_choice" == "Y" ]]; then
        certbot --nginx -d $DOMAIN_NAME -d www.$DOMAIN_NAME --non-interactive --agree-tos -m admin@$DOMAIN_NAME
        log_success "SSL berhasil diinstall untuk $DOMAIN_NAME"
    else
        log_warning "SSL dilewati. Jalankan 'certbot --nginx -d $DOMAIN_NAME' nanti untuk setup SSL."
    fi
}

# ==========================================
# 11. Tampilkan Status
# ==========================================
step_show_status() {
    echo ""
    log_info "11. Status Instalasi:"
    echo "-----------------------------------"
    echo "Python:     $(python3 --version)"
    echo "Pip:        $(pip3 --version 2>/dev/null | awk '{print $2}')"
    echo "Django:     $($APP_DIR/venv/bin/python -m django --version 2>/dev/null)"
    echo "Nginx:      $(nginx -v 2>&1)"
    echo "Gunicorn:   $($APP_DIR/venv/bin/gunicorn --version 2>/dev/null)"
    # Cek DB
    if systemctl is-active --quiet mariadb; then
        echo "MariaDB:    Active"
    fi
    echo "-----------------------------------"
    echo "Direktori Proyek:  $APP_DIR/$PROJECT_NAME"
    echo "Virtual Env:       $APP_DIR/venv"
    echo "Gunicorn Socket:   /run/gunicorn-$DOMAIN_NAME.sock"
    echo "Nginx Config:      /etc/nginx/sites-available/$DOMAIN_NAME"
    echo "-----------------------------------"
    log_success "12. Selesai! Website Anda seharusnya sudah bisa diakses di http://$DOMAIN_NAME"
    echo ""
    log_info "Tips:"
    echo "  - Aktifkan virtualenv: source $APP_DIR/venv/bin/activate"
    echo "  - Restart Gunicorn:    systemctl restart gunicorn-$DOMAIN_NAME"
    echo "  - Restart Nginx:       systemctl restart nginx"
    echo "  - Cek log Gunicorn:    journalctl -u gunicorn-$DOMAIN_NAME"
    echo "  - Cek log Nginx:       tail -f /var/log/nginx/error.log"
}

# ==========================================
# Main Execution
# ==========================================
check_root
check_os

step_update_system
step_install_basics
step_setup_firewall
step_install_db
step_install_nginx
step_setup_django
step_configure_gunicorn
step_configure_nginx
step_setup_ssl
step_show_status

exit 0
