source .env
echo "Deploying for $domain"
docker network create internal-network

#Database Deployment
sleep 2
echo "Deploying MariaDB container"
mkdir -p $mysql_dir
docker run -d --net internal-network --name mariadb -v $mysql_dir:/var/lib/mysql -e MYSQL_ROOT_PASSWORD=$mysql_root_pass mariadb:10.2
sleep 10

docker exec -it mariadb mysql -u root -p$mysql_root_pass -e "create database $DB_NAME;"
docker exec -it mariadb mysql -u root -p$mysql_root_pass -e "CREATE USER '$DB_USER'@'%' IDENTIFIED BY '$DB_PASS';"
docker exec -it mariadb mysql -u root -p$mysql_root_pass -e "GRANT ALL PRIVILEGES ON portal.* TO '$DB_USER'@'%';"
docker exec -it mariadb mysql -u root -p$mysql_root_pass -e  "FLUSH PRIVILEGES;"

docker exec -it mariadb mysql -u root -p$mysql_root_pass -e "create database radius;"
docker exec -it mariadb mysql -u root -p$mysql_root_pass -e "CREATE USER 'radius'@'%' IDENTIFIED BY '$radius_db_pass';"
docker exec -it mariadb mysql -u root -p$mysql_root_pass -e "GRANT ALL PRIVILEGES ON radius.* TO 'radius'@'%';"
docker exec -it mariadb mysql -u root -p$mysql_root_pass -e  "FLUSH PRIVILEGES;"

#schema import for radius
docker exec -i mariadb sh -c 'exec mysql -u root -pkjhdkjsahd0981@3History radius' < $(pwd)/freeradius/schema.sql;

#Free Radius Deployment

sed -i -e '/password =/ s/= .*/= "'"$radius_db_pass"'"/' $(pwd)/freeradius/sql
echo "Deploying Free Radius container"
docker run --name my-radius -d -v $(pwd)/freeradius/users:/etc/raddb/users -v $(pwd)/freeradius/clients.conf:/etc/raddb/clients.conf -v $(pwd)/freeradius/sql:/etc/raddb/mods-available/sql freeradius/freeradius-server

#Coova portal Deployment

mkdir -p $(pwd)/certs/etc/letsencrypt
mkdir -p $(pwd)/certs/var/lib/letsencrypt
mkdir -p $(pwd)/certs/var/log/letsencrypt

sed -i 's/example.com/'$domain'/g' Dockerfile
mv $(pwd)/coovachilli/example.com-backup $(pwd)/coovachilli/$domain
mv $(pwd)/coovachilli/sites-available/* $(pwd)/coovachilli/sites-available/$domain.conf
sed -i 's/example.com/'$domain'/g' $(pwd)/coovachilli/sites-available/$domain.conf
sed -i -e '/DB\_USER =/ s/= .*/= "'"$DB_USER"'"/' $(pwd)/coovachilli/$domain/.env
sed -i -e '/DB\_PASS =/ s/= .*/= "'"$DB_PASS"'"/' $(pwd)/coovachilli/$domain/.env
sed -i -e '/DB\_NAME =/ s/= .*/= "'"$DB_NAME"'"/' $(pwd)/coovachilli/$domain/.env
sed -i -e '/TABLE\_NAME =/ s/= .*/= "'"$TABLE_NAME"'"/' $(pwd)/coovachilli/$domain/.env
sed -i -e '/BUSINESS\_NAME =/ s/= .*/= "'"$BUSINESS_NAME"'"/' $(pwd)/coovachilli/$domain/.env
sed -i -e '/REDIRECT\_URL =/ s/= .*/= "'"$REDIRECT_URL"'"/' $(pwd)/coovachilli/$domain/.env
sed -i -e '/UAM\_SECRET =/ s/= .*/= "'"$UAM_SECRET"'"/' $(pwd)/coovachilli/$domain/.env

docker build -t portal-image .
sleep 5
docker image list
mkdir dummy-data
echo "Test" > dummy-data/index.html

docker run -d --name my-apache-dummy -p 80:80 -v $(pwd)/dummy-data:/var/www/html portal-image
sudo docker run -it --rm \
	-v $(pwd)/certs/etc/letsencrypt:/etc/letsencrypt \
	-v $(pwd)/certs/var/lib/letsencrypt:/var/lib/letsencrypt \
	-v $(pwd)/dummy-data:/data/letsencrypt \
	-v $(pwd)/certs/var/log/letsencrypt:/var/log/letsencrypt \
	certbot/certbot \
	certonly --webroot \
	--email $email --agree-tos --no-eff-email \
	--webroot-path=/data/letsencrypt \
	-d $domain

sleep 5
docker stop my-apache-dummy
docker rm my-apache-dummy
rm -rf dummy-data

docker run -d --net internal-network --name portal -p 443:443 \
-v $(pwd)/coovachilli/apache2/apache2.conf:/etc/apache2/apache2.conf \
-v $(pwd)/coovachilli/$domain:/var/www/$domain \
-v $(pwd)/coovachilli/sites-available:/etc/apache2/sites-available/ \
-v $(pwd)/certs/etc/letsencrypt/live/$domain/cert.pem:/etc/letsencrypt/live/$domain/cert.pem \
-v $(pwd)/certs/etc/letsencrypt/live/$domain/fullchain.pem:/etc/letsencrypt/live/$domain/fullchain.pem \
-v $(pwd)/certs/etc/letsencrypt/live/$domain/privkey.pem:/etc/letsencrypt/live/$domain/privkey.pem \
portal-image

docker exec -it portal a2dissite 000-default.conf
docker exec -it portal a2ensite $domain
docker exec -it portal a2enmod ssl
docker exec -it portal service apache2 reload

ufw allow 80:80/tcp
ufw allow 443:443/tcp
