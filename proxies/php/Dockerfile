# Imagen de demostración: el servidor integrado de PHP. En producción, el
# mismo código detrás de php-fpm + nginx o de Apache (ver README.md).
#
#   docker build -t nativ-maps-proxy-php .
#   docker run -p 8080:8080 -e PROXY_TOKEN=… -e AWS_REGION=us-east-1 \
#     -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY nativ-maps-proxy-php

FROM composer:2.8 AS vendor
WORKDIR /app
COPY composer.json composer.lock ./
COPY src ./src
RUN composer install --no-dev --no-interaction --no-progress --prefer-dist --optimize-autoloader

FROM php:8.3-cli
WORKDIR /app
COPY --from=vendor /app/vendor ./vendor
COPY src ./src
COPY public ./public
# Varios procesos: el servidor integrado atiende de uno en uno si no.
ENV PORT=8080 PHP_CLI_SERVER_WORKERS=4
EXPOSE 8080
USER www-data
CMD ["sh", "-c", "exec php -S 0.0.0.0:${PORT} public/index.php"]
