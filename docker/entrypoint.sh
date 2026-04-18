#!/usr/bin/env bash

set -o errexit # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Exit if any command in a pipeline fails (not just the last one).
set -o nounset # Treat unset variables as an error and exit immediately.
# set -o xtrace # Enable debug mode to print each command before executing it.

# Make sure all environment variables are set and not empty. If any variable is missing, the script will exit with an error.
REQUIRED_VARS=(
  DB_HOST
  MYSQL_DATABASE
  MYSQL_USER
  MYSQL_PASSWORD
  MEMCACHED_HOST
  ELASTICSEARCH_HOST
  GEARMAND_HOST
  ATOM_ADMIN_USERNAME
  ATOM_ADMIN_EMAIL
  ATOM_ADMIN_PASSWORD
  ATOM_SITE_TITLE
  ATOM_SITE_DESCRIPTION
  ATOM_SITE_BASE_URL
)
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "Error: Environment variable '$var' is not set or is empty. Please set it before running the container."
    exit 1
  fi
done

# If USE_S3FS is set to true, then validate that all required S3FS-related environment variables are set and not empty.
if [ "$USE_S3FS" = "true" ]; then
  REQUIRED_VARS_S3FS=(
    AWS_S3_BUCKET
    AWS_S3_ACCESS_KEY_ID
    AWS_S3_SECRET_ACCESS_KEY
    AWS_S3_URL
    ATOM_STATIC_URL
  )
  for var in "${REQUIRED_VARS_S3FS[@]}"; do
    if [ -z "${!var:-}" ]; then
      echo "Error: Environment variable '$var' is required when USE_S3FS is set to 'true'. Please set it before running the container."
      exit 1
    fi
  done
fi

# Determine the directory of the script
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure mounted cache & uploads directories are writable by the runtime user.
test -w "${__dir}/../cache" || (echo "Error: Cache directory is not writable. Check permissions." && exit 1)
test -w "${__dir}/../uploads" || (echo "Error: Uploads directory is not writable. Check permissions." && exit 1)

# Clear default php-fpm configuration to avoid conflicts with our custom configuration.
rm -rf /usr/local/etc/php-fpm.d/*

# Populate configuration files
php ${__dir}/bootstrap.php $@
status=$?
if [ $status -ne 0 ]; then
    echo "Error: Failed to populate configuration files. Check the error messages above for details."
    exit $status
fi

case $1 in
    '')
        echo "Usage: (convenience shortcuts)"
        echo "  ./entrypoint.sh worker      Execute worker."
        echo "  ./entrypoint.sh fpm         Execute php-fpm."
        echo "  ./entrypoint.sh init        Execute initialization script."
        echo ""
        echo "You can also pass other commands:"
        echo "  ./entrypoint.sh bash"
        echo "  ./entrypoint.sh uptime"
        echo "  ./entrypoint.sh ls -l /"
        exit 0
        ;;
    'worker')
        # Give some extra time to MySQL and Gearman to start
        # and add some interval in between restarts.
        sleep 10
        exec php ${__dir}/../symfony jobs:worker
        ;;
    'fpm')
        echo "Starting php-fpm and nginx..."
        # If S3FS is enabled, use the nginx configuration that serves static files from S3
        if [ "$USE_S3FS" = "true" ]; then
          echo "Using nginx configuration for S3FS."
          rm -f /etc/nginx/nginx.conf
          cp /etc/nginx/nginx-s3fs.conf /etc/nginx/nginx.conf
          echo "Nginx configuration for S3FS has been applied."
        fi
        echo "Starting php-fpm"
        php-fpm -D
        echo "Starting nginx"
        nginx -g 'daemon off;'
        ;;
    'init')
        echo "Performing initialization tasks..."

        # Check if instance has been initialized before
        if php symfony tools:get-version; then
          echo "Instance already initialized. Skipping initialization tasks."

          echo "Applying configuration settings from environment variables (if set)..."
          # Set site title
          php symfony tools:settings set siteTitle "${ATOM_SITE_TITLE:-My Atom Site}"
          echo "Site title set to: ${ATOM_SITE_TITLE:-My Atom Site}"
          # Set site description
          php symfony tools:settings set siteDescription "${ATOM_SITE_DESCRIPTION:-Welcome to My Atom Site}"
          echo "Site description set to: ${ATOM_SITE_DESCRIPTION:-Welcome to My Atom Site}"
          # Set site base URL
          php symfony tools:settings set siteBaseUrl "${ATOM_SITE_BASE_URL:-http://127.0.0.1}"
          echo "Site base URL set to: ${ATOM_SITE_BASE_URL:-http://127.0.0.1}"

          exit 0
        else
          echo "Instance has not been initialized. Proceeding with initialization..."

          # Run installer command
          php -d memory_limit=-1 symfony tools:install \
            --database-host=${DB_HOST:-db} \
            --database-port=${DB_PORT:-3306} \
            --database-name=${MYSQL_DATABASE:-atom_db} \
            --database-user=${MYSQL_USER:-atom_user} \
            --database-password=${MYSQL_PASSWORD:-atompassword123} \
            --search-host=${ELASTICSEARCH_HOST:-elasticsearch} \
            --search-port=${ELASTICSEARCH_PORT:-9200} \
            --search-index=atom \
            --site-title="${ATOM_SITE_TITLE:-My Atom Site}" \
            --site-description="${ATOM_SITE_DESCRIPTION:-Welcome to My Atom Site}" \
            --site-base-url="${ATOM_SITE_BASE_URL:-http://127.0.0.1}" \
            --admin-username=${ATOM_ADMIN_USERNAME:-admin} \
            --admin-email=${ATOM_ADMIN_EMAIL:-admin@example.com} \
            --admin-password=${ATOM_ADMIN_PASSWORD:-admin} \
            --no-confirmation
        fi

        echo "Initialization complete."
        exit 0
        ;;
esac

exec "${@}"
