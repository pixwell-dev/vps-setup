#!/bin/bash


echo '
 /$$$$$$$  /$$                                   /$$ /$$       /$$    /$$ /$$$$$$$   /$$$$$$                              /$$
| $$__  $$|__/                                  | $$| $$      | $$   | $$| $$__  $$ /$$__  $$                            | $$
| $$  \ $$ /$$ /$$   /$$ /$$  /$$  /$$  /$$$$$$ | $$| $$      | $$   | $$| $$  \ $$| $$  \__/        /$$$$$$$  /$$$$$$  /$$$$$$   /$$   /$$  /$$$$$$
| $$$$$$$/| $$|  $$ /$$/| $$ | $$ | $$ /$$__  $$| $$| $$      |  $$ / $$/| $$$$$$$/|  $$$$$$        /$$_____/ /$$__  $$|_  $$_/  | $$  | $$ /$$__  $$
| $$____/ | $$ \  $$$$/ | $$ | $$ | $$| $$$$$$$$| $$| $$       \  $$ $$/ | $$____/  \____  $$      |  $$$$$$ | $$$$$$$$  | $$    | $$  | $$| $$  \ $$
| $$      | $$  >$$  $$ | $$ | $$ | $$| $$_____/| $$| $$        \  $$$/  | $$       /$$  \ $$       \____  $$| $$_____/  | $$ /$$| $$  | $$| $$  | $$
| $$      | $$ /$$/\  $$|  $$$$$/$$$$/|  $$$$$$$| $$| $$         \  $/   | $$      |  $$$$$$/       /$$$$$$$/|  $$$$$$$  |  $$$$/|  $$$$$$/| $$$$$$$/
|__/      |__/|__/  \__/ \_____/\___/  \_______/|__/|__/          \_/    |__/       \______/       |_______/  \_______/   \___/   \______/ | $$____/
                                                                                                                                           | $$
                                                                                                                                           | $$
                                                                                                                                           |__/
';


# =================== YOUR DATA ========================

read -p 'Server name (example.com): ' SERVER_NAME
read -p 'Server ip: ' SERVER_IP


USER="admin"

source /root/.digitalocean_password
MYSQL_ROOT_PASSWORD=$root_mysql_pass

# fix locale
sudo locale-gen en_US.UTF-8
export LANGUAGE=en_US.UTF-8
export LC_ALL=en_US.UTF-8
sudo update-locale
echo "LANGUAGE=en_US.UTF-8" >> /etc/default/locale
echo "LC_ALL=en_US.UTF-8" >> /etc/default/locale


apt-get update && apt-get upgrade -y && apt-get autoremove -y

# Disable Password Authentication Over SSH

sed -i "/PasswordAuthentication yes/d" /etc/ssh/sshd_config
echo "" | sudo tee -a /etc/ssh/sshd_config
echo "" | sudo tee -a /etc/ssh/sshd_config
echo "PasswordAuthentication no" | sudo tee -a /etc/ssh/sshd_config

# Restart SSH

ssh-keygen -A
service ssh restart


# Create The Root SSH Directory If Necessary

if [ ! -d /root/.ssh ]
then
    mkdir -p /root/.ssh
    touch /root/.ssh/authorized_keys
fi

# Setup User

useradd $USER
mkdir -p /home/$USER/.ssh
adduser $USER sudo

cp /root/.ssh/authorized_keys /home/$USER/.ssh/authorized_keys

# Setup Site Directory Permissions

chown -R $USER:$USER /home/$USER
chmod -R 755 /home/$USER
chmod 700 /home/$USER/.ssh/id_rsa



echo 'start install nginx';
apt-get install nginx -y

# Command will change conf in /etc/nginx/nginx.conf file.
#   [] Change server_names_hash_bucket_size to value 64
#   [] Change worker_processes to auto
#   [] Change multi_accept to on
#   [] Change server_tokens to off for better server security (hide system info for others)

for f in 's/# server_names_hash_bucket_size.*/server_names_hash_bucket_size 64;/' 's/worker_processes.*/worker_processes auto;/' 's/# multi_accept.*/multi_accept on;/' 's/# server_tokens.*/server_tokens off;/'; do sed -i "$f" /etc/nginx/nginx.conf; done

# Disable The Default Nginx Site

rm /etc/nginx/sites-enabled/default
rm /etc/nginx/sites-available/default
service nginx restart


cat > /etc/nginx/sites-available/$SERVER_NAME << EOF
server {
    listen 80;
    server_name www.$SERVER_NAME $SERVER_NAME;
    root /var/www/$SERVER_NAME/public;
    index index.html index.htm index.php;
    charset utf-8;
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }
    access_log off;
    error_log  /var/log/nginx/$SERVER_NAME-error.log error;
    error_page 404 /index.php;
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php/php7.2-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
    }
    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -s /etc/nginx/sites-available/$SERVER_NAME /etc/nginx/sites-enabled/

service nginx restart
service nginx reload


# Add User To www-data Group

#usermod -a -G www-data $USER
#id $USER
#groups $USER

sudo apt-get install software-properties-common -y
# Add some repositories to system
for f in ppa:ondrej/php ppa:certbot/certbot; do apt-add-repository $f -y; done && apt-get update


apt-get install mysql-server -y
read -p 'DB name: ' databaseName

mysql --user="root" --password="$MYSQL_ROOT_PASSWORD" -e "GRANT ALL ON *.* TO root@'$SERVER_IP' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';"
mysql --user="root" --password="$MYSQL_ROOT_PASSWORD" -e "GRANT ALL ON *.* TO root@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';"
service mysql restart

mysql --user="root" --password="$MYSQL_ROOT_PASSWORD" -e "CREATE USER '$USER'@'$SERVER_IP' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';"
mysql --user="root" --password="$MYSQL_ROOT_PASSWORD" -e "GRANT ALL ON *.* TO '$USER'@'$SERVER_IP' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD' WITH GRANT OPTION;"
mysql --user="root" --password="$MYSQL_ROOT_PASSWORD" -e "GRANT ALL ON *.* TO '$USER'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD' WITH GRANT OPTION;"
mysql --user="root" --password="$MYSQL_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"

mysql --user="$USER" --password="$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE $databaseName CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"


apt-get install php7.2 php7.2-fpm php7.2-mysql php7.2-sqlite3 php7.2-intl php7.2-mbstring php7.2-gd php7.2-zip php7.2-json php7.2-curl php7.2-xml -y


# Command will change configuration in /etc/php/7.1/fpm/php.ini file.
#   [] Change cgi.fix_pathinfo to value 0
#   [] Increase memory_limit to 512 MB
#   [] Increase upload_max_filesize to 32 MB
#   [] Increase post_max_size to 32 MB
for f in 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' 's/memory_limit = .*/memory_limit = 512M/' 's|upload_max_filesize = 2M|upload_max_filesize = 32M|g' 's|post_max_size = 8M|post_max_size = 32M|g'; do sed -i "$f" /etc/php/7.2/fpm/php.ini; done && systemctl restart php7.2-fpm


ufw --force reset && ufw --force enable && ufw default deny incoming && ufw default allow outgoing
for f in ssh 'Nginx Full' 3306; do ufw allow "$f"; done

# Install Composer
sudo apt-get install composer -y


# Install & Configure Redis Server

apt-get install -y redis-server
# sed -i 's/bind 127.0.0.1/bind 0.0.0.0/' /etc/redis/redis.conf
service redis-server restart

# Install & Configure Memcached

apt-get install -y memcached
# sed -i 's/-l 127.0.0.1/-l 0.0.0.0/' /etc/memcached.conf
service memcached restart

# Install & Configure Beanstalk

apt-get install -y --force-yes beanstalkd
# sed -i "s/BEANSTALKD_LISTEN_ADDR.*/BEANSTALKD_LISTEN_ADDR=0.0.0.0/" /etc/default/beanstalkd
sed -i "s/#START=yes/START=yes/" /etc/default/beanstalkd
sed -i "s/#BEANSTALKD_EXTRA=\"-b /var/lib/beanstalkd\"/BEANSTALKD_EXTRA=\"-z 524280 -b /var/lib/beanstalkd\"/" /etc/default/beanstalkd
/etc/init.d/beanstalkd start


# cerbot
sudo apt-get install -y python-certbot-nginx
certbot --nginx -d $SERVER_NAME -d www.$SERVER_NAME --email monitor@pixwell.sk

#cat >> /etc/nginx/sites-available/$SERVER_NAME << EOF

#server {
#  listen 443 ssl;
#  server_name $SERVER_NAME;

#  ssl_certificate /etc/letsencrypt/live/$SERVER_NAME/fullchain.pem; # managed by Certbot
#  ssl_certificate_key /etc/letsencrypt/live/$SERVER_NAME/privkey.pem; # managed by Certbot
#  include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot

#  return 301 https://www.$SERVER_NAME$request_uri;
#}
#EOF


# Supervisor
sudo apt install -y supervisor
sudo usermod -a -G $USER ubuntu

sed -i "s/chmod=0700/chmod=0770/" /etc/supervisor/supervisord.conf
sed -i "/chmod=0770/achown=root:$USER" /etc/supervisor/supervisord.conf


touch /etc/supervisor/conf.d/laravel-worker.conf

cat > /etc/supervisor/conf.d/laravel-worker.conf << EOF
[program:laravel-queue-worker]
process_name=%(program_name)s_%(process_num)02d
command=sudo php /var/www/$SERVER_NAME/artisan queue:work beanstalkd --tries=3 --queue=default
user=root
autostart=true
autorestart=true
numprocs=5
redirect_stderr=true
stdout_logfile=/var/www/$SERVER_NAME/storage/logs/laravel-queue-worker.log
EOF

supervisorctl reread
supervisorctl update
sudo supervisorctl start laravel-queue-worker:*

apt-get purge apache2* -y && rm -rf /etc/apache2 && HTML_PATH="/var/www/html" &&  mv "$HTML_PATH/index.nginx-debian.html" "$HTML_PATH/index.html" && apt-get clean && reboot
