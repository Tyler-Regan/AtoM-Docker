#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset
# set -o xtrace

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Clean-ups
rm -rf /usr/local/etc/php-fpm.d/*
rm -rf ${__dir}/../cache/*

# Populate configuration files
php ${__dir}/bootstrap.php $@
status=$?
if [ $status -ne 0 ]; then
    echo "bootstrap.php failed!"
    exit $status
fi

case $1 in
    '')
        echo "Usage: (convenience shortcuts)"
        echo "  ./entrypoint.sh worker      Execute worker."
        echo "  ./entrypoint.sh fpm         Execute php-fpm."
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
        php-fpm -D --allow-to-run-as-root
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
