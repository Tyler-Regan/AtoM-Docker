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
        # Run database migrations
        php symfony tools:upgrade-sql --no-confirmation
        echo "Database migrations completed."

        # Populate search index
        php symfony search:populate
        echo "Search index populated."

        # Set site title
        php symfony tools:settings set siteTitle "${ATOM_SITE_TITLE:-My Atom Site}"
        echo "Site title set to: ${ATOM_SITE_TITLE:-My Atom Site}"
        # Set site description
        php symfony tools:settings set siteDescription "${ATOM_SITE_DESCRIPTION:-Welcome to My Atom Site}"
        echo "Site description set to: ${ATOM_SITE_DESCRIPTION:-Welcome to My Atom Site}"
        # Set site base URL
        php symfony tools:settings set siteBaseUrl "${ATOM_SITE_BASE_URL:-http://127.0.0.1}"
        echo "Site base URL set to: ${ATOM_SITE_BASE_URL:-http://127.0.0.1}"

        # Create admin user if not exists
        ADMIN_CREATE=$(php symfony tools:add-superuser --email="${ATOM_ADMIN_EMAIL:-admin@example.com}" --password="${ATOM_ADMIN_PASSWORD:-admin}" ${ATOM_ADMIN_USERNAME:-admin})
        if [ $ADMIN_CREATE -eq 0 ]; then
          echo "Admin user created with username: ${ATOM_ADMIN_USERNAME:-admin}"
        else
          echo "Admin user already exists or failed to create."
        fi

        echo "Initialization complete."
        ;;
esac

exec "${@}"
