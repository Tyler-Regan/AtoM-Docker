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
      gnu-libiconv \
    && npm install -g "less@<4.0.0"

COPY composer.* /usr/share/nginx/atom/build/
RUN set -xe && composer install -d /usr/share/nginx/atom/build

COPY package* /usr/share/nginx/atom/build/
RUN set -xe && npm ci --prefix /usr/share/nginx/atom/build

COPY . /usr/share/nginx/atom

WORKDIR /usr/share/nginx/atom

RUN set -xe \
    && mv /usr/share/nginx/atom/build/vendor/composer vendor/ \
    && mv /usr/share/nginx/atom/build/node_modules . \
    && npm run build \
    && rm -rf /usr/share/nginx/atom/build/

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
    && curl -Ls https://archive.apache.org/dist/xmlgraphics/fop/binaries/fop-2.1-bin.tar.gz | tar xz -C /usr/share \
    && ln -sf /usr/share/fop-2.1/fop /usr/local/bin/fop

COPY --from=php-ext-builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=php-ext-builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

COPY docker/etc/nginx/nginx.conf /etc/nginx/nginx.conf
RUN set -xe \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

COPY --from=app-builder --chown=www-data:www-data /usr/share/nginx/atom /usr/share/nginx/atom

WORKDIR /usr/share/nginx/atom


ENTRYPOINT ["docker/entrypoint.sh"]

CMD ["fpm"]
