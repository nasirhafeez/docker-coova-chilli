FROM ubuntu:22.04

ARG domain=example.com

ARG DEBIAN_FRONTEND=noninteractive

RUN apt update

RUN apt-get update -y && apt-get install -y apache2 nano curl php --allow-unauthenticated php-pear php-curl php-dev php-xml php-gd php-mbstring php-zip php-mysql php-xmlrpc libapache2-mod-php certbot python3-certbot-apache git mysql-client wget cron

RUN rm -rf /var/lib/apt/lists/* && apt clean

WORKDIR /var/www/

RUN mkdir $domain

WORKDIR /var/www/$domain/public

RUN echo "0 23 * * * certbot renew --dry-run" | crontab -

EXPOSE 80 443

CMD ["/usr/sbin/apache2ctl", "-D", "FOREGROUND"]

