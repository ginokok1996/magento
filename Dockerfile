#############################
# 		   Php         		#
#############################
FROM php:7.4-fpm

ARG MAGENTO_ROOT=/app

ENV PHP_MEMORY_LIMIT 2G
ENV PHP_VALIDATE_TIMESTAMPS 1
ENV DEBUG false
ENV MAGENTO_RUN_MODE production
ENV UPLOAD_MAX_FILESIZE 64M
ENV SENDMAIL_PATH /dev/null
ENV PHPRC ${MAGENTO_ROOT}/php.ini

ENV PHP_EXTENSIONS bcmath bz2 calendar exif gd gettext intl mysqli opcache pdo_mysql redis soap sockets sodium sysvmsg sysvsem sysvshm xsl zip pcntl

# Install dependencies
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
    apt-utils \
    sendmail-bin \
    sendmail \
    sudo \
    iproute2 \
    git \
    libbz2-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libfreetype6-dev \
    libgeoip-dev \
    wget \
    libgmp-dev \
    libgpgme11-dev \
    libmagickwand-dev \
    libmagickcore-dev \
    libicu-dev \
    libldap2-dev \
    libpspell-dev \
    libtidy-dev \
    libxslt1-dev \
    libyaml-dev \
    libzip-dev \
    zip \
    && rm -rf /var/lib/apt/lists/*

# Install MailHog
RUN curl -L -O https://github.com/mailhog/mhsendmail/releases/download/v0.2.0/mhsendmail_linux_amd64 \
    && sudo chmod +x mhsendmail_linux_amd64 \
    && sudo mv mhsendmail_linux_amd64 /usr/local/bin/mhsendmail

# Configure the gd library
RUN docker-php-ext-configure \
    gd --with-freetype=/usr/include/ --with-jpeg=/usr/include/
RUN docker-php-ext-configure \
    ldap --with-libdir=lib/x86_64-linux-gnu
RUN docker-php-ext-configure \
    opcache --enable-opcache

# Install required PHP extensions
RUN docker-php-ext-install -j$(nproc) \
    bcmath \
    bz2 \
    calendar \
    exif \
    gd \
    gettext \
    gmp \
    intl \
    ldap \
    mysqli \
    opcache \
    pdo_mysql \
    pspell \
    shmop \
    soap \
    sockets \
    sysvmsg \
    sysvsem \
    sysvshm \
    tidy \
    xmlrpc \
    xsl \
    zip \
    pcntl

RUN pecl install -o -f \
    geoip-1.1.1 \
    gnupg \
    igbinary \
    imagick \
    mailparse \
    msgpack \
    oauth \
    pcov \
    propro \
    raphf \
    redis \
    yaml

RUN curl -A "Docker" -o /tmp/blackfire-probe.tar.gz -D - -L -s https://blackfire.io/api/v1/releases/probe/php/linux/amd64/$(php -r "echo PHP_MAJOR_VERSION.PHP_MINOR_VERSION;") \
    && mkdir -p /tmp/blackfire \
    && tar zxpf /tmp/blackfire-probe.tar.gz -C /tmp/blackfire \
    && mv /tmp/blackfire/blackfire-*.so $(php -r "echo ini_get ('extension_dir');")/blackfire.so \
    && echo blackfire.agent_socket=tcp://blackfire:8707 > $(php -i | grep "additional .ini" | awk '{print $9}')/blackfire.ini \
    && rm -rf /tmp/blackfire /tmp/blackfire-probe.tar.gz
RUN mkdir -p /tmp/zoo \
    && cd /tmp/zoo \
    && git clone https://github.com/php-zookeeper/php-zookeeper.git \
    && curl -LO https://archive.apache.org/dist/zookeeper/zookeeper-3.4.14/zookeeper-3.4.14.tar.gz \
    && tar -xf zookeeper-3.4.14.tar.gz \
    && cp zookeeper-3.4.14/zookeeper-client/zookeeper-client-c/generated/zookeeper.jute.h zookeeper-3.4.14/zookeeper-client/zookeeper-client-c/include \
    && cd zookeeper-3.4.14/zookeeper-client/zookeeper-client-c \
    && ./configure \
    && sed -i 's/CFLAGS = -g -O2 -D_GNU_SOURCE/CFLAGS = -g -O2 -D_GNU_SOURCE -Wno-error=format-overflow -Wno-error=stringop-truncation/g' Makefile \
    && make \
    && make install \
    && ldconfig \
    && cd /tmp/zoo/php-zookeeper \
    && phpize \
    && ./configure --with-libzookeeper-dir=../zookeeper-3.4.14/zookeeper-client/zookeeper-client-c \
    && make \
    && make install
RUN rm -f /usr/local/etc/php/conf.d/*sodium.ini \
    && rm -f /usr/local/lib/php/extensions/*/*sodium.so \
    && apt-get remove libsodium* -y \
    && mkdir -p /tmp/libsodium \
    && curl -sL https://github.com/jedisct1/libsodium/archive/1.0.18-RELEASE.tar.gz | tar xzf - -C  /tmp/libsodium \
    && cd /tmp/libsodium/libsodium-1.0.18-RELEASE/ \
    && ./configure \
    && make && make check \
    && make install \
    && cd / \
    && rm -rf /tmp/libsodium \
    && pecl install -o -f libsodium
RUN cd /tmp \
    && curl -O https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz \
    && tar zxvf ioncube_loaders_lin_x86-64.tar.gz \
    && export PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;") \
    && export PHP_EXT_DIR=$(php-config --extension-dir) \
    && cp "./ioncube/ioncube_loader_lin_${PHP_VERSION}.so" "${PHP_EXT_DIR}/ioncube.so" \
    && rm -rf ./ioncube \
    && rm ioncube_loaders_lin_x86-64.tar.gz

COPY .docker/php/conf/php-fpm.ini /usr/local/etc/php/conf.d/zz-magento.ini
COPY .docker/php/conf/php-pcov.ini /usr/local/etc/php/conf.d/zz-pcov-settings.ini
COPY .docker/php/conf/mail.ini /usr/local/etc/php/conf.d/zz-mail.ini
COPY .docker/php/conf/php-fpm.conf /usr/local/etc/
COPY .docker/php/conf/php-gnupg.ini /usr/local/etc/php/conf.d/gnupg.ini

RUN groupadd -g 1000 www && useradd -g 1000 -u 1000 -d ${MAGENTO_ROOT} -s /bin/bash www

COPY .docker/php/docker-entrypoint.sh /docker-entrypoint.sh
RUN ["chmod", "+x", "/docker-entrypoint.sh"]

RUN mkdir -p ${MAGENTO_ROOT}

VOLUME ${MAGENTO_ROOT}

RUN chown -R www:www /usr/local /var/www /var/log /usr/local/etc/php/conf.d ${MAGENTO_ROOT}

ENTRYPOINT ["/docker-entrypoint.sh"]

WORKDIR ${MAGENTO_ROOT}

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer
ENV COMPOSER_ALLOW_SUPERUSER=1

COPY /app /app

RUN composer config --global http-basic.repo.magento.com ce7e9740272307af36caad68f054f144 d4975ceefe2051768b2e01b9796f53a0
RUN composer install --prefer-dist --no-dev --no-scripts --no-progress --no-suggest --ignore-platform-reqs
RUN composer dump-autoload --classmap-authoritative --no-dev

USER root

CMD ["php-fpm", "-R"]