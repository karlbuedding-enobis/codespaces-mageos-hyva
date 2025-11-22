#!/bin/bash

set -eu

# ======================================================================================
# Environment and Service Configuration
# ======================================================================================
USE_MAGEOS="${USE_MAGEOS:=YES}"
INSTALL_MAGENTO="${INSTALL_MAGENTO:=YES}"
INSTALL_SAMPLE_DATA="${INSTALL_SAMPLE_DATA:=YES}"
HYVA_LICENCE_KEY="${HYVA_LICENCE_KEY:=''}"
HYVA_PROJECT_NAME="${HYVA_PROJECT_NAME:=''}"
CODESPACES_REPO_ROOT="${CODESPACES_REPO_ROOT:=$(pwd)}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:=password}"
MAGENTO_ADMIN_USERNAME="${MAGENTO_ADMIN_USERNAME:=admin}"
MAGENTO_ADMIN_PASSWORD="${MAGENTO_ADMIN_PASSWORD:=password1}"
MAGENTO_ADMIN_EMAIL="${MAGENTO_ADMIN_EMAIL:=admin@example.com}"
COMPOSER_COMMAND="php -d memory_limit=-1 $(which composer)"
OPENSEARCH_CONTAINER="opensearch-node"

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

# Determine platform name for display
if [ "${USE_MAGEOS}" = "YES" ]; then
  PLATFORM_NAME="mage-os"
else
  PLATFORM_NAME="magento"
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
sudo cp "${CODESPACES_REPO_ROOT}/.devcontainer/config/.gitignore" ${CODESPACES_REPO_ROOT}/.gitignore

source "${CODESPACES_REPO_ROOT}/.devcontainer/scripts/start_services.sh"

cd "${CODESPACES_REPO_ROOT}"

# Fix permissions for nginx/PHP-FPM to access Magento files
echo "Setting proper file permissions for web server access..."
if [ -d "${CODESPACES_REPO_ROOT}/pub" ]; then
    # Read permissions for nginx (nobody user)
    sudo find "${CODESPACES_REPO_ROOT}" -type d -exec chmod o+rx {} \; 2>/dev/null || true
    sudo find "${CODESPACES_REPO_ROOT}" -type f -exec chmod o+r {} \; 2>/dev/null || true

    # Write permissions for PHP-FPM (vscode user) on writable directories
    echo "Setting ownership and permissions for writable directories..."
    sudo chown -R vscode:vscode "${CODESPACES_REPO_ROOT}/var" "${CODESPACES_REPO_ROOT}/generated" "${CODESPACES_REPO_ROOT}/pub/static" "${CODESPACES_REPO_ROOT}/pub/media" "${CODESPACES_REPO_ROOT}/app/etc" 2>/dev/null || true
    sudo find "${CODESPACES_REPO_ROOT}/var" "${CODESPACES_REPO_ROOT}/generated" "${CODESPACES_REPO_ROOT}/pub/static" "${CODESPACES_REPO_ROOT}/pub/media" "${CODESPACES_REPO_ROOT}/app/etc" -type f -exec chmod 664 {} \; 2>/dev/null || true
    sudo find "${CODESPACES_REPO_ROOT}/var" "${CODESPACES_REPO_ROOT}/generated" "${CODESPACES_REPO_ROOT}/pub/static" "${CODESPACES_REPO_ROOT}/pub/media" "${CODESPACES_REPO_ROOT}/app/etc" -type d -exec chmod 775 {} \; 2>/dev/null || true

    echo "File permissions updated successfully"
fi

if [ -f ".devcontainer/db-installed.flag" ]; then
  echo "${PLATFORM_NAME} already installed, skipping installation/import."
  if [ "${HYVA_LICENCE_KEY}" ]; then
    echo "Configuring and building Hyvä theme..."

    # Ensure Hyva theme is set as active theme
    echo "Activating Hyvä theme..."
    php -d memory_limit=-1 bin/magento config:set design/theme/theme_id 5 --scope=default --scope-code=0

    # Build Hyva theme
    echo "Building Hyvä theme assets..."
    n98-magerun2 dev:theme:build-hyva frontend/Hyva/default

    # Deploy static content for Hyva theme
    echo "Deploying static content for Hyvä theme..."
    php -d memory_limit=-1 bin/magento setup:static-content:deploy -f -t Hyva/default

    # Clear cache
    php -d memory_limit=-1 bin/magento cache:flush

    echo "Hyvä theme configured successfully"
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

        # Configure Composer to allow insecure packages
        echo "Configuring Composer to bypass security advisories..."
        ${COMPOSER_COMMAND} config --global audit.block-insecure false

        # Create project in temp directory then move files
        TEMP_DIR=$(mktemp -d)
        echo "Using temporary directory: ${TEMP_DIR}"

        if [ "${USE_MAGEOS}" = "YES" ]; then
            echo "Installing Mage-OS from https://repo.mage-os.org/"
            ${COMPOSER_COMMAND} create-project --repository-url=https://repo.mage-os.org/ mage-os/project-community-edition ${TEMP_DIR} --no-interaction --ignore-platform-reqs
        else
            echo "Installing Magento from https://repo.magento.com/"
            if [ -n "${MAGENTO_COMPOSER_AUTH_USER}" ] && [ -n "${MAGENTO_COMPOSER_AUTH_PASS}" ]; then
                ${COMPOSER_COMMAND} config --global http-basic.repo.magento.com ${MAGENTO_COMPOSER_AUTH_USER} ${MAGENTO_COMPOSER_AUTH_PASS}
            fi
            ${COMPOSER_COMMAND} create-project --repository-url=https://repo.magento.com/ magento/project-community-edition:${MAGENTO_VERSION} ${TEMP_DIR} --no-interaction --ignore-platform-reqs
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

        # Configure Composer to allow insecure packages
        echo "Configuring Composer to bypass security advisories..."
        ${COMPOSER_COMMAND} config --global audit.block-insecure false

        ${COMPOSER_COMMAND} install --no-dev --optimize-autoloader --ignore-platform-reqs
    fi

    # Install Sample Data if enabled
    if [ "${INSTALL_SAMPLE_DATA}" = "YES" ]; then
        echo "============ Installing Sample Data =========="
        if [ "${USE_MAGEOS}" = "YES" ]; then
            echo "**** Deploying Mage-OS sample data ****"
            # Mage-OS uses the same sample data as Magento
            ${COMPOSER_COMMAND} require mage-os/module-bundle-sample-data mage-os/module-widget-sample-data mage-os/module-theme-sample-data mage-os/module-catalog-sample-data mage-os/module-customer-sample-data mage-os/module-cms-sample-data mage-os/module-catalog-rule-sample-data mage-os/module-sales-rule-sample-data mage-os/module-review-sample-data mage-os/module-tax-sample-data mage-os/module-sales-sample-data mage-os/module-grouped-product-sample-data mage-os/module-downloadable-sample-data mage-os/module-msrp-sample-data mage-os/module-configurable-sample-data mage-os/module-product-links-sample-data mage-os/module-wishlist-sample-data mage-os/module-swatches-sample-data --no-update
            ${COMPOSER_COMMAND} update --ignore-platform-reqs
        else
            echo "**** Deploying Magento sample data ****"
            php -d memory_limit=-1 bin/magento sampledata:deploy
            ${COMPOSER_COMMAND} update --ignore-platform-reqs
        fi
        echo "**** Sample data deployed successfully ****"
    fi

    if [ "${INSTALL_MAGENTO}" = "YES" ] && [ "${HYVA_LICENCE_KEY}" ]; then
        echo "**** Configuring Hyvä Theme ****"
        ${COMPOSER_COMMAND} config --auth http-basic.hyva-themes.repo.packagist.com token ${HYVA_LICENCE_KEY}
        ${COMPOSER_COMMAND} config repositories.private-packagist composer https://hyva-themes.repo.packagist.com/${HYVA_PROJECT_NAME}/
        ${COMPOSER_COMMAND} require hyva-themes/magento2-default-theme

        echo "**** Activating Hyvä Theme ****"
        # Run setup:upgrade to register the new theme
        php -d memory_limit=-1 bin/magento setup:upgrade

        # Set Hyva as the active theme
        php -d memory_limit=-1 bin/magento config:set design/theme/theme_id 5 --scope=default --scope-code=0

        echo "Hyvä theme installed and activated"
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

    # Run setup:upgrade if sample data was installed
    if [ "${INSTALL_SAMPLE_DATA}" = "YES" ]; then
      echo "============ Running setup:upgrade to install sample data =========="
      php -d memory_limit=-1 bin/magento setup:upgrade
    fi
else
  echo "============ ${PLATFORM_NAME} is installed, copying CS env.php ============"
  cp ${CODESPACES_REPO_ROOT}/.devcontainer/config/env.php ${CODESPACES_REPO_ROOT}/app/etc/env.php
  sed -i "s|codespaces.domain|https://${CODESPACE_NAME}-8080.app.github.dev|g" ${CODESPACES_REPO_ROOT}/app/etc/env.php
fi;
  php -d memory_limit=-1 bin/magento deploy:mode:set developer
  php -d memory_limit=-1 bin/magento config:set catalog/search/engine opensearch
  php -d memory_limit=-1 bin/magento config:set catalog/search/opensearch_server_hostname localhost
  php -d memory_limit=-1 bin/magento config:set catalog/search/opensearch_server_port 9200
  php -d memory_limit=-1 bin/magento indexer:reindex
  php -d memory_limit=-1 bin/magento cache:flush

  # Fix permissions after Magento installation/configuration
  echo "Setting proper file permissions after Magento setup..."
  # Read permissions for nginx (nobody user)
  sudo find "${CODESPACES_REPO_ROOT}" -type d -exec chmod o+rx {} \; 2>/dev/null || true
  sudo find "${CODESPACES_REPO_ROOT}" -type f -exec chmod o+r {} \; 2>/dev/null || true

  # Write permissions for PHP-FPM (vscode user) on writable directories
  echo "Setting ownership and permissions for writable directories..."
  sudo chown -R vscode:vscode "${CODESPACES_REPO_ROOT}/var" "${CODESPACES_REPO_ROOT}/generated" "${CODESPACES_REPO_ROOT}/pub/static" "${CODESPACES_REPO_ROOT}/pub/media" "${CODESPACES_REPO_ROOT}/app/etc" 2>/dev/null || true
  sudo find "${CODESPACES_REPO_ROOT}/var" "${CODESPACES_REPO_ROOT}/generated" "${CODESPACES_REPO_ROOT}/pub/static" "${CODESPACES_REPO_ROOT}/pub/media" "${CODESPACES_REPO_ROOT}/app/etc" -type f -exec chmod 664 {} \; 2>/dev/null || true
  sudo find "${CODESPACES_REPO_ROOT}/var" "${CODESPACES_REPO_ROOT}/generated" "${CODESPACES_REPO_ROOT}/pub/static" "${CODESPACES_REPO_ROOT}/pub/media" "${CODESPACES_REPO_ROOT}/app/etc" -type d -exec chmod 775 {} \; 2>/dev/null || true

  echo "File permissions updated successfully"

  # Install Claude agents
  git clone https://github.com/rubenzantingh/claude-code-magento-agents
  mkdir -p ~/.claude/agents
  cp -r "$(pwd)/claude-code-magento-agents/" ~/.claude/agents
  rm -rf ./claude-code-magento-agents

  ## MISC
  echo "Patch the X-frame-options to allow quick view"
  url="https://${CODESPACE_NAME}-8080.app.github.dev/"
  target="${CODESPACES_REPO_ROOT}/vendor/${PLATFORM_NAME}/framework/App/Response/HeaderProvider/XFrameOptions.php"
  sed -i "s|\$this->headerValue = \$xFrameOpt;|\$this->headerValue = '${url}';|" "$target"
  # echo "Fetching Media Files"        
  # ./mc cp wasabi/clients.bamford/bam_media.zip ${CODESPACES_REPO_ROOT}/bam_media.zip
  # unzip -o ${CODESPACES_REPO_ROOT}/bam_media.zip -d ${CODESPACES_REPO_ROOT}/pub/ && rm ./bam_media.zip
fi

show_ready_message

touch "${CODESPACES_REPO_ROOT}/.devcontainer/db-installed.flag"

if [ "${HYVA_LICENCE_KEY}" ]; then
  echo "Final Hyvä theme configuration..."

  # Build Hyva theme assets
  n98-magerun2 dev:theme:build-hyva frontend/Hyva/default

  # Deploy static content for Hyva theme
  echo "Deploying static content for Hyvä theme..."
  php -d memory_limit=-1 bin/magento setup:static-content:deploy -f -t Hyva/default

  # Clear cache to ensure theme changes are visible
  php -d memory_limit=-1 bin/magento cache:flush

  echo "Hyvä theme fully configured and ready"
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