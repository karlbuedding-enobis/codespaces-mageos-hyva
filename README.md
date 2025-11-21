# Codespaces + Mage-OS + Hyvä Development Environment

A complete GitHub Codespaces development setup for Mage-OS (Magento Open Source) with Hyvä theme integration. This configuration provides a fully-featured, pre-configured development environment that launches in minutes.

## Stack

- **PHP**: 8.3-FPM
- **Web Server**: Nginx
- **Database**: MariaDB 10.6
- **Search**: OpenSearch 2.19.2
- **Cache**: Redis
- **Mail Testing**: Mailpit
- **Node.js**: 18.x
- **Database Management**: phpMyAdmin
- **Magento Version**: 2.4.7-p5
- **Theme**: Hyvä

## Features

- **Flexible Platform Installation**: Choose between Mage-OS or Magento via `USE_MAGEOS` flag
- Automated installation and configuration
- Pre-configured services (Nginx, MariaDB, Redis, OpenSearch)
- Modular service management with Supervisor and start_services.sh
- Hyvä theme build automation
- Docker-in-Docker support for additional containers (Mailpit, OpenSearch, phpMyAdmin)
- n98-magerun2 CLI tool pre-installed
- AI CLI tools (Gemini CLI, Claude Code) pre-installed
- Awesome Claude Agents collection auto-installed from GitHub
- X-frame-options patched for quick view support
- Persistent installation detection (skips reinstall on restart)
- Xdebug pre-installed for debugging

## Prerequisites

- GitHub account with Codespaces access
- Required secrets configured in your repository:
  - `HYVA_LICENCE_KEY`: Hyvä license key (token for authentication)
  - `HYVA_PROJECT_NAME`: Hyvä project name for Packagist repository access

- Optional secrets (only needed if `USE_MAGEOS=NO`):
  - `MAGENTO_COMPOSER_AUTH_USER`: Adobe Commerce Marketplace username
  - `MAGENTO_COMPOSER_AUTH_PASS`: Adobe Commerce Marketplace password


## Getting Started

1. **Create a new Codespace** from this repository

2. **Automated Setup Process**:

   The setup runs in two phases:

   **Phase 1 - Container Creation** (`setup.sh` via `onCreateCommand`):
   - Installs AI CLI tools (Gemini CLI, Claude Code)
   - Starts Docker containers (Mailpit, OpenSearch, phpMyAdmin)

   **Phase 2 - Application Setup** (`start.sh` via `postAttachCommand`):
   - Configures and starts Supervisor services (Nginx, MariaDB, Redis, PHP-FPM)
   - Waits for MySQL and OpenSearch to become ready
   - Installs Node.js using `n` package manager
   - Creates project using `composer create-project`:
     - **If `USE_MAGEOS=YES`**: Installs Mage-OS from https://repo.mage-os.org/
     - **If `USE_MAGEOS=NO`**: Installs Magento from https://repo.magento.com/
   - Installs fresh instance or uses existing database
   - Configures with Redis for sessions, cache, and page cache
   - Configures OpenSearch as the search engine
   - Installs Awesome Claude Agents from GitHub
   - Patches X-frame-options for quick view support
   - Builds the Hyvä theme (if license key provided)
   - Creates `.devcontainer/db-installed.flag` to skip reinstall on subsequent starts

3. **Access your store**:
   - Frontend: `https://[your-codespace-name]-8080.app.github.dev/`
   - Admin Panel: `https://[your-codespace-name]-8080.app.github.dev/admin`

## Default Credentials

### Magento Admin
- **Username**: `admin`
- **Password**: `password1`
- **Email**: `admin@example.com`

### Database
- **Root Password**: `password`
- **Database Name**: `magento2`

## Available Services & Ports

| Service | Port | Description |
|---------|------|-------------|
| Nginx | 8080 | Magento web interface |
| MariaDB | 3306 | Database server |
| phpMyAdmin | 8081 | Database management UI |
| Redis | 6379 | Cache and session storage |
| OpenSearch | 9200 | Search engine API |
| OpenSearch Node | 9600 | OpenSearch node communication |
| Mailpit SMTP | 1025 | Mail SMTP server |
| Mailpit Web | 8025 | Mail testing UI |

## Common Commands

### Magento CLI
```bash
# Clear cache
bin/magento cache:flush

# Reindex
bin/magento indexer:reindex

# Deploy static content
bin/magento setup:static-content:deploy -f

# Enable developer mode
bin/magento deploy:mode:set developer

# Run setup upgrade
bin/magento setup:upgrade
```

### Hyvä Theme
```bash
# Build Hyvä theme
n98-magerun2 dev:theme:build-hyva

# Build specific theme
n98-magerun2 dev:theme:build-hyva frontend/Hyva/default
```

### n98-magerun2
```bash
# List all commands
n98-magerun2 list

# Check system info
n98-magerun2 sys:info

# Check module status
n98-magerun2 module:list
```

### Service Management
```bash
# Check all service status (custom script)
.devcontainer/scripts/status.sh

# Check Supervisor services
sudo supervisorctl status

# Restart a service
sudo supervisorctl restart nginx
sudo supervisorctl restart php-fpm

# Reload Supervisor configuration (after config changes)
sudo supervisorctl reread
sudo supervisorctl update

# Check Docker containers
docker ps

# View container logs
docker logs mailpit
docker logs opensearch-node
docker logs phpmyadmin
```

### Database Access
```bash
# MySQL CLI access
mysql -u root -ppassword magento2

# Or use n98-magerun2
n98-magerun2 db:console
```

## Configuration Files

Key configuration files are located in `.devcontainer/`:

**Config Directory** (`.devcontainer/config/`):
- `nginx.conf` - Nginx web server configuration
- `sp-php-fpm.conf` - PHP-FPM supervisor configuration
- `mysql.cnf` - MariaDB server configuration
- `mysql.conf` - MariaDB supervisor configuration
- `client.cnf` - MySQL client configuration
- `sp-redis.conf` - Redis supervisor configuration
- `sp-nginx.conf` - Nginx supervisor configuration
- `sp-opensearch.conf` - OpenSearch supervisor configuration (if used)
- `env.php` - Pre-configured Magento environment file (for existing installations)

**Scripts Directory** (`.devcontainer/scripts/`):
- `setup.sh` - Initial setup (runs during container creation)
- `start.sh` - Application startup (runs on container attach)
- `start_services.sh` - Modular service management (sourced by start.sh)
- `status.sh` - Service status checker

## Troubleshooting

### Services Not Starting
Check supervisor status:
```bash
sudo supervisorctl status
```

Restart all services:
```bash
sudo supervisorctl restart all
```

### Database Connection Issues
Verify MariaDB is running:
```bash
sudo mysqladmin ping
```

Check MySQL logs:
```bash
sudo tail -f /var/log/mysql/error.log
```

### OpenSearch Issues
Check OpenSearch status:
```bash
curl http://localhost:9200/_cluster/health?pretty
```

View OpenSearch logs:
```bash
docker logs opensearch-node
```

### Clear Magento Cache
```bash
bin/magento cache:flush
bin/magento cache:clean
rm -rf var/cache/* var/page_cache/* generated/*
```

### Reinstallation
To trigger a fresh installation, delete the flag file:
```bash
rm .devcontainer/db-installed.flag
```

Then restart the Codespace. The `start.sh` script will detect the missing flag and run the full installation process again, including:
- Fresh Magento installation (if `INSTALL_MAGENTO=YES`)
- Database recreation
- Composer dependencies installation
- Hyvä theme configuration
- All setup steps from scratch

**Note**: The flag file is created at the end of `start.sh` (line 141) to prevent reinstallation on subsequent container restarts.

## Development Workflow

1. **Make code changes** in your IDE
2. **Clear Magento cache** if needed: `bin/magento cache:flush`
3. **Rebuild Hyvä theme** if template changes: `n98-magerun2 dev:theme:build-hyva`
4. **Test changes** in your browser
5. **Commit and push** to your repository

## Notes

- The first startup may take 10-15 minutes as it installs Magento and all dependencies
- Subsequent starts are much faster (2-3 minutes) as the `.devcontainer/db-installed.flag` prevents reinstallation
- The environment uses Redis for sessions, cache, and full page cache
- OpenSearch runs in a Docker container with security disabled for development ease
- Xdebug is installed but not enabled by default
- Awesome Claude Agents are automatically cloned and installed to `~/.claude/agents`
- X-frame-options are patched to allow Magento's quick view functionality
- Services are managed through Supervisor with automatic restart policies
- Docker containers (Mailpit, OpenSearch, phpMyAdmin) have `--restart unless-stopped` policies

## Advanced Configuration

### Choosing Between Mage-OS and Magento

By default, this environment installs **Mage-OS** (set via `USE_MAGEOS=YES`). To install Magento instead:

1. Edit `.devcontainer/devcontainer.json`:
   ```json
   "USE_MAGEOS": "NO"
   ```

2. Ensure you have configured the required Magento Composer credentials:
   - `MAGENTO_COMPOSER_AUTH_USER`
   - `MAGENTO_COMPOSER_AUTH_PASS`

**Key Differences**:
- **Mage-OS**: Community-driven fork, no Adobe Marketplace access by default
- **Magento**: Official Adobe version, requires Marketplace credentials, access to Marketplace extensions

**Note**: If using Mage-OS and you need Marketplace extensions, you'll need to configure `repo.magento.com` separately with appropriate credentials.

### Changing Magento Version
Edit `.devcontainer/devcontainer.json` and modify:
```json
"MAGENTO_VERSION": "2.4.7-p5"
```

### Using an Existing Magento Database
To skip fresh installation and use an existing database:
1. Set `INSTALL_MAGENTO: "NO"` in `.devcontainer/devcontainer.json`
2. Place your pre-configured `env.php` in `.devcontainer/config/env.php`
3. The `start.sh` script will copy this file to `app/etc/env.php` and update the base URL

### Adding Custom Composer Repositories
Edit your `composer.json` or use:
```bash
composer config repositories.custom-repo vcs https://github.com/your/repo
```

### Environment Variables
All environment variables can be customized in `.devcontainer/devcontainer.json` under `containerEnv`:

**Key Environment Variables**:
- `USE_MAGEOS` - Set to "YES" for Mage-OS, "NO" for Magento (default: "YES")
- `INSTALL_MAGENTO` - Set to "YES" for fresh install, "NO" to use existing database (default: "YES")
- `MAGENTO_VERSION` - Magento version to install when `USE_MAGEOS=NO` (default: "2.4.7-p5")
- `MAGENTO_ADMIN_USERNAME` - Admin username (default: "admin")
- `MAGENTO_ADMIN_PASSWORD` - Admin password (default: "password1")
- `MAGENTO_ADMIN_EMAIL` - Admin email (default: "admin@example.com")
- `MYSQL_ROOT_PASSWORD` - MySQL root password (default: "password")
- `HYVA_LICENCE_KEY` - Your Hyvä license token (required for Hyvä installation)
- `HYVA_PROJECT_NAME` - Your Hyvä project name for Packagist access (required for Hyvä installation)

## License

This development environment configuration is provided as-is. Individual components (Magento, Hyvä, etc.) have their own licenses.

## Support

For issues with:
- **Magento**: Refer to [Mage-OS Documentation](https://mage-os.org/)
- **Hyvä Theme**: Refer to [Hyvä Documentation](https://docs.hyva.io/)
- **This Setup**: Open an issue in this repository
