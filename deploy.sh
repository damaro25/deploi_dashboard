#!/bin/bash
set -e

function print_info() {
    echo "====================================================================="
    echo "$1"
    echo "====================================================================="
}

v_php="8.2"
SITE_NAME="192.168.1.100"
DB_NAME="dashbord"
DB_USER="dash_user"
DB_PASSWORD="DashBord2025@@"
DB_HOST="127.0.0.1"
PG_VERSION="16"
PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"
HBA_CONF="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
ADMIN_EMAIL="karamocra19945@gmail.com"
ADMIN_NAME="Administrator"
ADMIN_PASSWORD="Admin1234!!"
CLONE_DIR="/var/www"
PROJECT_NAME="first_dashBord"
PROJECT_DIR="$CLONE_DIR/$PROJECT_NAME"

function install_dependencies() {
    print_info "📦 Mise à jour des paquets et installation des dépendances de base"
    sudo apt-get update
    sudo apt-get install -y software-properties-common curl unzip git
}

function install_requirements() {
    print_info "🗄️ Installation de PostgreSQL, Redis, PostGIS, Apache2"
    sudo apt-get install -y postgresql postgresql-contrib postgresql-client-common redis mysql-server apache2

    PG_VERSION=$(psql -V | awk '{print $3}' | cut -d. -f1)
    sudo apt-get install -y postgis postgresql-${PG_VERSION}-postgis-3
}
#Database PostgreSQL config
create_non_root_user(){
    if id "$DB_USER" &>/dev/null; then
        print_info "ℹ️ L'utilisateur Linux '$DB_USER' existe déjà"
    else
        sudo useradd -m "$DB_USER"
        echo "${DB_USER}:${DB_PASSWORD}" | sudo chpasswd
        sudo usermod -aG sudo "$DB_USER"
        echo "✅ Utilisateur '$DB_USER' succès"
    fi
}
setup_postgresql_database() {
    sudo -u postgres psql <<EOF || error_exit "Échec de la création."
CREATE DATABASE $DB_NAME;
CREATE ROLE $DB_USER WITH
  LOGIN
  SUPERUSER
  CREATEDB
  CREATEROLE
  REPLICATION
  BYPASSRLS
  PASSWORD '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
\c $DB_NAME
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO $DB_USER;
EOF
}

configure_remote_access() {
    print_info "Config remote access PostgreSQL..."

    sudo  sed -i "s/^#listen_addresses = 'localhost'/listen_addresses = '*'/" $PG_CONF
    sudo sed -i "s/^listen_addresses = 'localhost'/listen_addresses = '*'/" $PG_CONF

    if grep -q "^host\s\+all\s\+all\s\+0.0.0.0/0\s\+md5" $HBA_CONF; then
       sudo sed -i "s/^host\s\+all\s\+all\s\+0.0.0.0\/0\s\+md5/host    all     all     0.0.0.0\/0    md5/" $HBA_CONF
    else
        sudo echo "host    all     all     0.0.0.0/0    md5" | sudo tee -a $HBA_CONF
    fi
}

restart_postgresql() {
    print_info "Restart PostgreSQL..."
    sudo systemctl restart postgresql || error_exit "Echec Restart."
    sudo systemctl enable postgresql || error_exit "Échec activation PostgreSQL."
}

configure_firewall() {
    print_info "allow 5432..."
    #sudo ufw allow 5432/tcp || error_exit "Deny access port 5432."
}

function test_connection() {
    print_info "Connexion distante..."
    PGPASSWORD=$DB_PASSWORD psql -U $DB_USER -d $DB_NAME -h $DB_HOST -c "\dt" || error_exit "Echec connexion"
}

function install_php() {
    print_info "🐘 Installation de PHP ${v_php} avec les modules nécessaires"
    sudo add-apt-repository -y ppa:ondrej/php
    sudo apt-get update
    sudo apt-get install -y php${v_php} php${v_php}-cli php${v_php}-fpm php${v_php}-common \
        php${v_php}-mysql php${v_php}-zip php${v_php}-gd php${v_php}-sqlite3 php${v_php}-mbstring \
        php${v_php}-curl php${v_php}-xml php${v_php}-bcmath php${v_php}-intl \
        php${v_php}-redis php${v_php}-pgsql \
        libapache2-mod-php${v_php} libapache2-mod-fcgid apache2-suexec-pristine \
        libapache2-mod-python zlib1g-dev libzip-dev
}

###Configuration de MYSQl
function configure_mysql_database {
    MYSQL_CONF="/etc/mysql/mysql.conf.d/mysqld.cnf"
    sudo sed -i "s/^bind-address\s*=.*/bind-address = 0.0.0.0/" "$MYSQL_CONF" || error_exit "Impossible $MYSQL_CONF"
    sudo systemctl restart mysql || error_exit "Échec du redémarrage de MySQL"
    #if sudo ufw status | grep -q active; then
    #sudo ufw allow 3306/tcp
    #fi

    print_info "✅ Configuration terminée : MySQL accepte maintenant les connexions distantes !"

    print_info "Configuration de la base de données MySQL"
    mysql -u root -p"${DB_PASSWORD}" <<EOF
CREATE DATABASE IF NOT EXISTS db_menage_ordinaire;
CREATE DATABASE IF NOT EXISTS  db_menage_collectif;
CREATE DATABASE  IF NOT EXISTS db_concession;
CREATE DATABASE  IF NOT EXISTS db_population_specifique;

CREATE DATABASE  IF NOT EXISTS menages;
CREATE DATABASE  IF NOT EXISTS db_gn_classroom;
CREATE DATABASE  IF NOT EXISTS db_gn_staff;
CREATE DATABASE  IF NOT EXISTS db_zd;
CREATE DATABASE  IF NOT EXISTS db_presence;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
SET GLOBAL log_bin_trust_function_creators = 1;

EOF
}

#####Installation Composer
function install_composer() {
    print_info "🎼 Installation de Composer"
    EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

    if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
        >&2 echo '❌ ERREUR : Checksum invalide.'
        rm -f composer-setup.php
        return 1
    fi

    php composer-setup.php --quiet
    RESULT=$?
    rm -f composer-setup.php

    if [ $RESULT -eq 0 ]; then
        echo "✅ Composer installé."
        sudo mv composer.phar /usr/local/bin/composer
        sudo chmod +x /usr/local/bin/composer
    else
        echo "❌ Échec de l’installation de Composer."
    fi

    return $RESULT
}

function install_project_dependencies() {
    print_info "📦 Installation des dépendances via Composer"

    composer create-project laravel/laravel "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    print_info "📦 Configuration initiale du projet Laravel"

   sudo chmod -R 777 "$PROJECT_DIR"
   sudo chown -R www-data:www-data "$PROJECT_DIR"

   composer require uneca/dashboard-starter-kit
   php artisan chimera:install

}
function configure_apache {
    print_info "Configuration d'Apache2"
    sudo sed -i 's/AllowOverride None/AllowOverride All/g' /etc/apache2/apache2.conf

    print_info "Création du fichier de configuration pour le site"
    sudo tee /etc/apache2/sites-available/${SITE_NAME}.conf > /dev/null <<EOF
<VirtualHost *:80>
    ServerName $SITE_NAME
    ServerAdmin webmaster@localhost
    DocumentRoot $CLONE_DIR/${PROJECT_NAME}/public

    <Directory $CLONE_DIR/${PROJECT_NAME}/public>
        Options indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/${PROJECT_NAME}.log
    CustomLog \${APACHE_LOG_DIR}/${PROJECT_NAME}.log combined
</VirtualHost>
EOF

    if [ ! -d "/etc/apache2/sites-available" ]; then
        sudo mkdir -p /etc/apache2/sites-available
    fi

    sudo a2ensite ${SITE_NAME}.conf
    sudo a2enmod rewrite
    sudo systemctl reload apache2
}

########

function run_env() {
    ENV_FILE="$PROJECT_DIR/.env"
    ENV_EXAMPLE="$PROJECT_DIR/.env.example"

    cd "$PROJECT_DIR" || exit 1

    if [ -f "$ENV_EXAMPLE" ]; then
        sudo cp "$ENV_EXAMPLE" "$ENV_FILE"
    else
        echo "Le fichier .env.example est introuvable dans $PROJECT_DIR"
        exit 1
    fi
    sudo sed -i "s|^DB_CONNECTION=.*|DB_CONNECTION=pgsql|" "$ENV_FILE"
    sudo sed -i "s|^DB_HOST=.*|DB_HOST=127.0.0.1|" "$ENV_FILE"
    sudo sed -i "s|^DB_PORT=.*|DB_PORT=5432|" "$ENV_FILE"
    sudo sed -i "s|^DB_DATABASE=.*|DB_DATABASE=$DB_NAME|" "$ENV_FILE"
    sudo sed -i "s|^DB_USERNAME=.*|DB_USERNAME=$DB_USER|" "$ENV_FILE"
    sudo sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$DB_PASSWORD|" "$ENV_FILE"
    sudo sed -i "s|^APP_URL=.*|APP_URL=$SITE_NAME|" "$ENV_FILE"
    php artisan chimera:install

    # ✅ Créer le dossier si absent
    if [ ! -d "$PROJECT_DIR/data-export" ]; then
        print_info "📂 Création du dossier data-export requis par chimera:data-import"
        mkdir -p "$PROJECT_DIR/data-export"
        touch "$PROJECT_DIR/data-export/.gitkeep"
    fi

#    php artisan chimera:data-import

    sudo chown www-data:www-data "$ENV_FILE"
    print_info "✅ .env configuré avec succès"
}

function php_chimera(){
     print_info "*****************************************************************************"
     php artisan migrate
     print_info "🧱 Installation de npm et configuration NVM"

    sudo apt install -y npm curl
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

    nvm install 20
    nvm use 20
    nvm alias default 20

# Installation des dépendances JS
   npm install
   npm run build
}
function create_super_admin() {
    if ! command -v expect &>/dev/null; then
        echo "🛠 Installation de 'expect'..."
        sudo apt-get install -y expect
    fi

    # Script interactif avec expect
    expect <<EOF
spawn php artisan adminify
expect "Email address"
send "$ADMIN_EMAIL\r"
expect "Name"
send "$ADMIN_NAME\r"
expect "Password"
send "$ADMIN_PASSWORD\r"
expect eof
EOF
}
install_dependencies
install_requirements
create_non_root_user
setup_postgresql_database
configure_remote_access
restart_postgresql
configure_firewall
test_connection
install_php
configure_mysql_database
install_composer
install_project_dependencies
configure_apache
run_env
php_chimera
create_super_admin