#!/usr/bin/env bash

set -o errexit # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Exit if any command in a pipeline fails (not just the last one).
set -o nounset # Treat unset variables as an error and exit immediately.
# set -o xtrace # Enable debug mode to print each command before executing it.

USE_S3FS="${USE_S3FS:-false}"

is_truthy() {
  case "${1,,}" in
    true|1|yes|on)
      return 0
      ;;
    false|0|no|off|'')
      return 1
      ;;
    *)
      echo "Error: USE_S3FS must be a boolean value (true/false, 1/0, yes/no, on/off). Got: '$1'"
      exit 1
      ;;
  esac
}

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[&|]/\\&/g'
}

render_s3_nginx_config() {
  local template="/etc/nginx/nginx-s3fs.conf"
  local atom_static_origin
  local atom_static_authority
  local atom_static_host
  local atom_static_base_path
  local static_url_parts=()

  if [ ! -r "$template" ]; then
    echo "Error: Nginx S3 template '$template' is not readable."
    exit 1
  fi

  mapfile -t static_url_parts < <(ATOM_STATIC_URL="$ATOM_STATIC_URL" php <<'PHP'
<?php
$url = getenv('ATOM_STATIC_URL');
$parts = parse_url($url);

if (false === $parts || !isset($parts['scheme'], $parts['host'])) {
    fwrite(STDERR, "Error: ATOM_STATIC_URL must be a valid absolute http(s) URL.\n");
    exit(1);
}

$scheme = strtolower($parts['scheme']);
if (!in_array($scheme, ['http', 'https'], true)) {
    fwrite(STDERR, "Error: ATOM_STATIC_URL must use the http or https scheme.\n");
    exit(1);
}

if (isset($parts['user']) || isset($parts['pass'])) {
    fwrite(STDERR, "Error: ATOM_STATIC_URL must not include credentials.\n");
    exit(1);
}

if (str_contains($parts['host'], '*')) {
    fwrite(STDERR, "Error: ATOM_STATIC_URL must use a concrete host name; wildcard hosts are not supported for nginx proxying.\n");
    exit(1);
}

if (isset($parts['query']) || isset($parts['fragment'])) {
    fwrite(STDERR, "Error: ATOM_STATIC_URL must not include a query string or fragment.\n");
    exit(1);
}

$host = $parts['host'];
$authority = $host . (isset($parts['port']) ? ':' . $parts['port'] : '');
$path = rtrim($parts['path'] ?? '', '/');

if ('' !== $path && '/' !== $path[0]) {
    fwrite(STDERR, "Error: ATOM_STATIC_URL must use an absolute path when a path is provided.\n");
    exit(1);
}

if ('/' === $path) {
    $path = '';
}

echo $scheme . '://' . $authority, PHP_EOL;
echo $authority, PHP_EOL;
echo $host, PHP_EOL;
echo $path, PHP_EOL;
PHP
  )

  if [ "${#static_url_parts[@]}" -ne 4 ]; then
    echo "Error: Failed to derive nginx S3 proxy settings from ATOM_STATIC_URL."
    exit 1
  fi

  atom_static_origin="${static_url_parts[0]}"
  echo "Derived ATOM_STATIC_ORIGIN: $atom_static_origin"
  atom_static_authority="${static_url_parts[1]}"
  echo "Derived ATOM_STATIC_AUTHORITY: $atom_static_authority"
  atom_static_host="${static_url_parts[2]}"
  echo "Derived ATOM_STATIC_HOST: $atom_static_host"
  atom_static_base_path="${static_url_parts[3]}"
  echo "Derived ATOM_STATIC_BASE_PATH: $atom_static_base_path"

  sed \
    -e "s|__ATOM_STATIC_ORIGIN__|$(escape_sed_replacement "$atom_static_origin")|g" \
    -e "s|__ATOM_STATIC_AUTHORITY__|$(escape_sed_replacement "$atom_static_authority")|g" \
    -e "s|__ATOM_STATIC_HOST__|$(escape_sed_replacement "$atom_static_host")|g" \
    -e "s|__ATOM_STATIC_BASE_PATH__|$(escape_sed_replacement "$atom_static_base_path")|g" \
    "$template" > /tmp/nginx.conf

  echo "Nginx S3 proxy target resolved from ATOM_STATIC_URL: ${atom_static_origin}${atom_static_base_path}"
}

configure_nginx() {
  local source_config="/etc/nginx/nginx.conf"

  if is_truthy "$USE_S3FS"; then
    echo "Using nginx configuration for S3FS."
    render_s3_nginx_config
  else
    echo "Using default nginx configuration."
    if [ ! -r "$source_config" ]; then
      echo "Error: Nginx configuration '$source_config' is not readable."
      exit 1
    fi

    cp "$source_config" /tmp/nginx.conf
  fi

  echo "Nginx configuration prepared at /tmp/nginx.conf."
}

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

# If USE_S3FS is enabled, validate that all required S3FS-related environment variables are set and not empty.
if is_truthy "$USE_S3FS"; then
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
php "${__dir}/bootstrap.php" "$@"
status=$?
if [ $status -ne 0 ]; then
    echo "Error: Failed to populate configuration files. Check the error messages above for details."
    exit $status
fi

case "${1:-}" in
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
        exec php ${__dir}/../symfony jobs:worker
        ;;
    'fpm')
        echo "Starting php-fpm and nginx..."
        configure_nginx
        echo "Starting php-fpm"
        php-fpm -D
        echo "Starting nginx"
        nginx -c /tmp/nginx.conf -g 'daemon off;'
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
