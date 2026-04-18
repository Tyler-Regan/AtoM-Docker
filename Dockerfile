FROM php:8.3-fpm-alpine AS php-ext-builder

ARG MEMCACHE_VERSION=8.2

RUN set -xe \
    && apk add --no-cache --virtual .phpext-builddeps \
      gettext-dev \
      libxslt-dev \
      zlib-dev \
      libmemcached-dev \
      libzip-dev \
      oniguruma-dev \
      autoconf \
      build-base \
      openldap-dev \
      linux-headers \
    && docker-php-ext-install \
      calendar \
      gettext \
      mbstring \
      mysqli \
      opcache \
      pcntl \
      pdo_mysql \
      sockets \
      xsl \
      zip \
      ldap \
    && pecl install apcu pcov \
    && curl -Ls "https://github.com/websupport-sk/pecl-memcache/archive/refs/tags/${MEMCACHE_VERSION}.tar.gz" | tar xz -C / \
    && cd "/pecl-memcache-${MEMCACHE_VERSION}" \
    && phpize && ./configure && make && make install \
    && cd / && rm -rf "/pecl-memcache-${MEMCACHE_VERSION}" \
    && docker-php-ext-enable apcu memcache pcov \
    && echo "extension=ldap.so" > /usr/local/etc/php/conf.d/docker-php-ext-ldap.ini \
    && pecl clear-cache

FROM php-ext-builder AS app-builder

ENV COMPOSER_ALLOW_SUPERUSER=1 \
    LD_PRELOAD=/usr/lib/preloadable_libiconv.so

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

RUN set -xe \
    && apk add --no-cache \
      npm \
      make \
      bash \
      gnu-libiconv

COPY composer.* /atom/build/
RUN set -xe && composer install -d /atom/build

COPY package* /atom/build/
RUN set -xe && npm ci --prefix /atom/build

COPY . /atom

WORKDIR /atom

RUN set -xe \
    && mv /atom/build/vendor/composer vendor/ \
    && mv /atom/build/node_modules . \
    && npm run build \
    && rm -rf /atom/build/

FROM php:8.3-fpm-alpine AS runtime

ENV FOP_HOME=/usr/share/fop-2.1 \
    LD_PRELOAD=/usr/lib/preloadable_libiconv.so

RUN set -xe \
    && apk add --no-cache \
      gettext \
      libxslt \
      libmemcached-libs \
      libzip \
      openldap \
      nginx \
      openjdk8-jre-base \
      ffmpeg \
      imagemagick \
      ghostscript \
      poppler-utils \
      bash \
      gnu-libiconv \
      fcgi \
      libcap \
    && addgroup -g 1000 -S atom \
    && adduser -u 1000 -S -D -G atom atom \
    && curl -Ls https://archive.apache.org/dist/xmlgraphics/fop/binaries/fop-2.1-bin.tar.gz | tar xz -C /usr/share \
    && ln -sf /usr/share/fop-2.1/fop /usr/local/bin/fop \
    && setcap 'cap_net_bind_service=+ep' /usr/sbin/nginx

COPY --from=php-ext-builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=php-ext-builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

COPY --from=app-builder --chown=atom:atom /atom /atom/src

COPY docker/etc/nginx/nginx-default.conf /etc/nginx/nginx.conf
COPY docker/etc/nginx/nginx-s3fs.conf /etc/nginx/nginx-s3fs.conf
RUN set -xe \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
    && mkdir -p /atom/src/cache /atom/src/uploads /run/php-fpm /var/lib/nginx /var/tmp/nginx \
    && chown -R atom:atom \
      /atom/src/cache \
      /atom/src/uploads \
      /run/php-fpm \
      /var/lib/nginx \
      /var/tmp/nginx \
      /var/log/nginx \
      /usr/local/etc/php \
      /usr/local/etc/php-fpm.d

WORKDIR /atom/src

USER atom

ENTRYPOINT ["docker/entrypoint.sh"]

CMD ["fpm"]
