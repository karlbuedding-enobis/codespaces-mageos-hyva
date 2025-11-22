#!/bin/bash

set -eu

# ======================================================================================
# Environment and Service Configuration
# ======================================================================================
USE_MAGEOS="${USE_MAGEOS:=YES}"
INSTALL_MAGENTO="${INSTALL_MAGENTO:=YES}"
HYVA_LICENCE_KEY="${HYVA_LICENCE_KEY:=''}"
HYVA_PROJECT_NAME="${HYVA_PROJECT_NAME:=''}"
CODESPACES_REPO_ROOT="${CODESPACES_REPO_ROOT:=$(pwd)}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:=password}"
MAGENTO_ADMIN_USERNAME="${MAGENTO_ADMIN_USERNAME:=admin}"
MAGENTO_ADMIN_PASSWORD="${MAGENTO_ADMIN_PASSWORD:=password1}"
MAGENTO_ADMIN_EMAIL="${MAGENTO_ADMIN_EMAIL:=admin@example.com}"
COMPOSER_COMMAND="php -d memory_limit=-1 $(which composer)"
OPENSEARCH_CONTAINER="opensearch-node"

# Determine platform name for display
if [ "${USE_MAGEOS}" = "YES" ]; then
  PLATFORM_NAME="Mage-OS"
else
  PLATFORM_NAME="Magento"
fi

# ======================================================================================
# Supervisor Services (Nginx, MariaDB, Redis)
# ======================================================================================
echo "Configuring Supervisor services..."

# Create runtime directory for Nginx before starting it
sudo mkdir -p /var/run/nginx

# Copy config files
sudo cp "${CODESPACES_REPO_ROOT}/.devcontainer/config/nginx.conf" /etc/nginx/nginx.conf
sudo sed -i "s|__CODESPACES_REPO_ROOT__|${CODESPACES_REPO_ROOT}|g" /etc/nginx/nginx.conf
sudo cp "${CODESPACES_REPO_ROOT}/.devcontainer/config/sp-php-fpm.conf" /etc/supervisor/conf.d/
sudo sed -i "s|\$CODESPACES_REPO_ROOT|${CODESPACES_REPO_ROOT}|g" /etc/supervisor/conf.d/sp-php-fpm.conf
sudo cp "${CODESPACES_REPO_ROOT}/.devcontainer/config/sp-redis.conf" /etc/supervisor/conf.d/
sudo cp "${CODESPACES_REPO_ROOT}/.devcontainer/config/mysql.conf" /etc/supervisor/conf.d/
sudo cp "${CODESPACES_REPO_ROOT}/.devcontainer/config/sp-nginx.conf" /etc/supervisor/conf.d/
sudo cp "${CODESPACES_REPO_ROOT}/.devcontainer/config/mysql.cnf" /etc/mysql/conf.d/
sudo cp "${CODESPACES_REPO_ROOT}/.devcontainer/config/client.cnf" /etc/mysql/conf.d/

source "${CODESPACES_REPO_ROOT}/.devcontainer/scripts/start_services.sh"

cd "${CODESPACES_REPO_ROOT}"

if [ -f ".devcontainer/db-installed.flag" ]; then
  echo "${PLATFORM_NAME} already installed, skipping installation/import."
  if [ "${HYVA_LICENCE_KEY}" ]; then
    echo "Running Hyvä Build"
    n98-magerun2 dev:theme:build-hyva frontend/Hyva/default
  fi;
  show_ready_message
  exit 0
else
    sudo npm install -g n
    sudo n latest

    echo "============ 1. Setup ${PLATFORM_NAME} Environment =========="

    # Check if composer.json exists, if not create the project
    if [ ! -f "composer.json" ]; then
        echo "**** Creating ${PLATFORM_NAME} project ****"
        echo "Updating PHP Memory Limit"
        echo "memory_limit=2G" | sudo tee -a /usr/local/etc/php/conf.d/docker-fpm.ini

        # Create project in temp directory then move files
        TEMP_DIR=$(mktemp -d)
        echo "Using temporary directory: ${TEMP_DIR}"

        if [ "${USE_MAGEOS}" = "YES" ]; then
            echo "Installing Mage-OS from https://repo.mage-os.org/"
            ${COMPOSER_COMMAND} create-project --repository-url=https://repo.mage-os.org/ mage-os/project-community-edition ${TEMP_DIR} --no-interaction --ignore-platform-reqs --no-audit
        else
            echo "Installing Magento from https://repo.magento.com/"
            if [ -n "${MAGENTO_COMPOSER_AUTH_USER}" ] && [ -n "${MAGENTO_COMPOSER_AUTH_PASS}" ]; then
                ${COMPOSER_COMMAND} config --global http-basic.repo.magento.com ${MAGENTO_COMPOSER_AUTH_USER} ${MAGENTO_COMPOSER_AUTH_PASS}
            fi
            ${COMPOSER_COMMAND} create-project --repository-url=https://repo.magento.com/ magento/project-community-edition:${MAGENTO_VERSION} ${TEMP_DIR} --no-interaction --ignore-platform-reqs --no-audit
        fi

        echo "Moving files from temporary directory to project root..."
        # Move all files except .git and .devcontainer
        shopt -s dotglob
        for file in ${TEMP_DIR}/*; do
            filename=$(basename "$file")
            if [ "$filename" != ".git" ] && [ "$filename" != ".devcontainer" ]; then
                mv "$file" ./ 2>/dev/null || echo "Skipping $filename"
            fi
        done
        shopt -u dotglob
        rm -rf ${TEMP_DIR}
        echo "Project files moved successfully"
        
    else
        echo "**** composer.json exists, running composer install ****"
        echo "Updating PHP Memory Limit"
        echo "memory_limit=2G" | sudo tee -a /usr/local/etc/php/conf.d/docker-fpm.ini
        ${COMPOSER_COMMAND} install --no-dev --optimize-autoloader --ignore-platform-reqs --no-audit
    fi

    if [ "${INSTALL_MAGENTO}" = "YES" ] && [ "${HYVA_LICENCE_KEY}" ]; then
        echo "**** Configuring Hyvä Theme ****"
        ${COMPOSER_COMMAND} config --auth http-basic.hyva-themes.repo.packagist.com token ${HYVA_LICENCE_KEY}
        ${COMPOSER_COMMAND} config repositories.private-packagist composer https://hyva-themes.repo.packagist.com/${HYVA_PROJECT_NAME}/
        ${COMPOSER_COMMAND} require hyva-themes/magento2-default-theme --no-audit
    fi


   # Decide whether to run a fresh install or import a database
   if [ "${INSTALL_MAGENTO}" = "YES" ]; then
    echo "============ Installing New ${PLATFORM_NAME} Instance ============"
    mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS magento2;"

    url="https://${CODESPACE_NAME}-8080.app.github.dev/"
    echo "Installing ${PLATFORM_NAME} with URL: $url"
    
    php -d memory_limit=-1 bin/magento setup:install \
      --db-name='magento2' \
      --db-user='root' \
      --db-host='127.0.0.1' \
      --db-password="${MYSQL_ROOT_PASSWORD}" \
      --base-url="$url" \
      --backend-frontname='admin' \
      --admin-user="${MAGENTO_ADMIN_USERNAME}" \
      --admin-password="${MAGENTO_ADMIN_PASSWORD}" \
      --admin-email="${MAGENTO_ADMIN_EMAIL}" \
      --admin-firstname='Admin' \
      --admin-lastname='User' \
      --language='en_GB' \
      --currency='GBP' \
      --timezone='Europe/London' \
      --use-rewrites='1' \
      --use-secure='1' \
      --base-url-secure="$url" \
      --use-secure-admin='1' \
      --session-save='redis' \
      --session-save-redis-host='127.0.0.1' \
      --session-save-redis-port='6379' \
      --cache-backend='redis' \
      --cache-backend-redis-server='127.0.0.1' \
      --cache-backend-redis-db='1' \
      --page-cache='redis' \
      --page-cache-redis-server='127.0.0.1' \
      --page-cache-redis-db='2' \
      --search-engine='opensearch' \
      --opensearch-host='localhost' \
      --opensearch-port='9200'
else
  echo "============ ${PLATFORM_NAME} is installed, copying CS env.php ============"
  cp ${CODESPACES_REPO_ROOT}/.devcontainer/config/env.php ${CODESPACES_REPO_ROOT}/app/etc/env.php
  sed -i "s|codespaces.domain|https://${CODESPACE_NAME}-8080.app.github.dev|g" ${CODESPACES_REPO_ROOT}/app/etc/env.php
fi;

  php -d memory_limit=-1 bin/magento config:set catalog/search/engine opensearch
  php -d memory_limit=-1 bin/magento config:set catalog/search/opensearch_server_hostname localhost
  php -d memory_limit=-1 bin/magento config:set catalog/search/opensearch_server_port 9200
  php -d memory_limit=-1 bin/magento indexer:reindex
  php -d memory_limit=-1 bin/magento cache:flush

  # Install Claude agents
  git clone https://github.com/vijaythecoder/awesome-claude-agents.git
  mkdir -p ~/.claude/agents
  cp -r "$(pwd)/awesome-claude-agents/agents/" ~/.claude/agents
  rm -rf ./awesome-claude-agents

  ## MISC
  echo "Patch the X-frame-options to allow quick view"
  url="https://${CODESPACE_NAME}-8080.app.github.dev/"
  target="${CODESPACES_REPO_ROOT}/vendor/magento/framework/App/Response/HeaderProvider/XFrameOptions.php"
  sed -i "s|\$this->headerValue = \$xFrameOpt;|\$this->headerValue = '${url}';|" "$target"
  # echo "Fetching Media Files"        
  # ./mc cp wasabi/clients.bamford/bam_media.zip ${CODESPACES_REPO_ROOT}/bam_media.zip
  # unzip -o ${CODESPACES_REPO_ROOT}/bam_media.zip -d ${CODESPACES_REPO_ROOT}/pub/ && rm ./bam_media.zip
fi

show_ready_message

touch "${CODESPACES_REPO_ROOT}/.devcontainer/db-installed.flag"

if [ "${HYVA_LICENCE_KEY}" ]; then
  n98-magerun2 dev:theme:build-hyva frontend/Hyva/default
fi;

# ======================================================================================
# Environment Ready Message
# ======================================================================================
show_ready_message() {
  echo "============ Environment Ready =========="
  echo "All services started successfully!"
  echo "You can check service status with: .devcontainer/scripts/status.sh"
  echo "And Docker containers with: docker ps"
  echo "Have an awesome time! 💙 Develo.co.uk"
}