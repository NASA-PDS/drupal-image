# NASA-PDS Drupal base image
#
# Adapted from the official Drupal image's Dockerfile
# (https://github.com/docker-library/drupal, 10.6/php8.3/apache-trixie).
#
# Differences from the official image:
#
# - No Drupal project is baked into /opt/drupal. Consumers (portal-drupal)
#   bind-mount or COPY their own Composer project there, which would shadow it.
# - The extension directory comes from `php-config` rather than `php -r`. PHP
#   CLI SIGSEGVs under QEMU when building linux/amd64 on Apple Silicon under
#   Podman/buildah.

ARG PHP_VERSION=8.3

# Pin linux/amd64 (AWS EC2). Podman/buildah ignores Compose `platform:`, so
# the Dockerfile must pin it itself.
FROM --platform=linux/amd64 docker.io/library/composer:2 AS composer

# https://www.drupal.org/docs/system-requirements/php-requirements
FROM --platform=linux/amd64 docker.io/library/php:${PHP_VERSION}-apache-trixie

LABEL org.opencontainers.image.title="nasapds/drupal" \
      org.opencontainers.image.description="PHP + Apache base image for NASA-PDS Drupal sites (no Drupal core baked in)" \
      org.opencontainers.image.source="https://github.com/NASA-PDS/drupal-image" \
      org.opencontainers.image.vendor="NASA Planetary Data System Engineering Node"

# install the PHP extensions we need
RUN set -eux; \
	\
# https://github.com/drupal/drupal/blob/d91d8d0a6d3ffe5f0b6dde8c2fbe81404843edc5/.htaccess (references both mod_expires and mod_rewrite explicitly)
	a2enmod expires rewrite; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libavif-dev \
		libfreetype6-dev \
		libjpeg-dev \
		libpng-dev \
		libpq-dev \
		libwebp-dev \
		libzip-dev \
	; \
	\
	docker-php-ext-configure gd \
		--with-avif \
		--with-freetype \
		--with-jpeg=/usr \
		--with-webp \
	; \
	\
	docker-php-ext-install -j "$(nproc)" \
		gd \
		pdo_mysql \
		pdo_pgsql \
		zip \
	; \
	\
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	ldd "$(php-config --extension-dir)"/*.so \
		| awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
		| sort -u \
		| xargs -r dpkg-query -S \
		| cut -d: -f1 \
		| sort -u \
		| xargs -rt apt-mark manual; \
	\
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=60'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

# https://www.drupal.org/node/3298550
# Drupal now recommends sites enable PHP output buffering by default, if PHP is run as a server module
# e.g. with Apache's mod_php
RUN { \
		echo 'output_buffering=true'; \
	} > /usr/local/etc/php/conf.d/docker-php-drupal-recommended.ini

COPY --from=composer /usr/bin/composer /usr/local/bin/composer

# https://github.com/docker-library/drupal/pull/259
# https://github.com/composer/composer/issues/11839
ENV COMPOSER_ALLOW_SUPERUSER=1

WORKDIR /opt/drupal
RUN set -eux; \
	mkdir -p /opt/drupal/web; \
	rmdir /var/www/html; \
	ln -sf /opt/drupal/web /var/www/html

ENV PATH=${PATH}:/opt/drupal/vendor/bin
