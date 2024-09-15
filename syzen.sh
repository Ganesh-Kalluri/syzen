#!/bin/bash

# Update and upgrade the system
sudo apt update
sudo apt upgrade -y

# Install Git and clone the repository
sudo apt install -y git
git clone https://github.com/Ganesh-Kalluri/delton.git leewise

# Install Python 3.10.11 from deadsnakes PPA
sudo apt install -y software-properties-common
sudo add-apt-repository ppa:deadsnakes/ppa -y
sudo apt update
sudo apt install -y python3.10 python3.10-venv python3.10-dev

# Update python3 symlink to point to python3.10
sudo rm /usr/bin/python3
sudo ln -s /usr/bin/python3.10 /usr/bin/python3

# Install pip for Python 3.10
sudo apt install -y curl
curl -sS https://bootstrap.pypa.io/get-pip.py | sudo python3.10
python3.10 -m pip install ipython

# Install PostgreSQL 16
sudo apt install wget ca-certificates -y
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
sudo apt update
sudo apt install -y postgresql-16 postgresql-client-16

# Create PostgreSQL user for Leewise
sudo -u postgres psql -c "CREATE USER leewise WITH SUPERUSER CREATEDB CREATEROLE LOGIN;"

# Set up the virtual environment and install dependencies
python3.10 -m venv ~/venv
source ~/venv/bin/activate
cd leewise
sudo apt install -y python3-pip libldap2-dev libpq-dev libsasl2-dev
pip install pyjwt
sudo apt install wkhtmltopdf
sudo apt install -y python3-pip
pip3 install pdfminer.six
python3.10 -m pip install -r requirements.txt

# Open ports for HTTP, PostgreSQL, Leewise, and Email services
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 8069 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 8072 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 5432 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 53 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 25 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 465 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 587 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 143 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 993 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 110 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 995 -j ACCEPT

# Install and configure Nginx
sudo apt install nginx -y
sudo ufw allow 'Nginx Full'
sudo ufw allow OpenSSH
sudo ufw enable

# Remove default site configs
sudo rm /etc/nginx/sites-enabled/default
sudo rm /etc/nginx/sites-available/default

# Create leewise Nginx config
cat <<EOL | sudo tee /etc/nginx/sites-available/leewise.conf
map $http_upgrade $connection_upgrade {
  default upgrade;
  ''      close;
}
server {
    server_name www.leewise.in;

    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Real-IP $remote_addr;
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    proxy_set_header X-Client-IP $remote_addr;

    access_log /var/log/nginx/leewise-access.log;
    error_log /var/log/nginx/leewise-error.log;

    proxy_buffers 16 64k;
    proxy_buffer_size 128k;

    proxy_read_timeout 900s;
    proxy_connect_timeout 900s;
    proxy_send_timeout 900s;

    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;

    types {
        text/less less;
        text/scss scss;
    }

    gzip on;
    gzip_min_length 1100;
    gzip_buffers 4 32k;
    gzip_types text/css text/less text/plain text/xml application/xml application/json application/javascript application/pdf image/jpeg image/png;
    gzip_vary on;
    client_header_buffer_size 4k;
    large_client_header_buffers 4 64k;
    client_max_body_size 0;

    location / {
        proxy_pass http://localhost:8069;
        proxy_redirect off;
    }

    location /websocket {
         proxy_pass http://localhost:8072;
         proxy_set_header Upgrade $http_upgrade;
         proxy_set_header Connection $connection_upgrade;
         proxy_set_header X-Forwarded-Host $host;
         proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
         proxy_set_header X-Forwarded-Proto $scheme;
         proxy_set_header X-Real-IP $remote_addr;
   }
    location ~* \.(js|css|png|jpg|jpeg|gif|ico)$ {
        expires 2d;
        proxy_pass http://localhost:8069;
        add_header Cache-Control "public, no-transform";
    }

    location ~ /[a-zA-Z0-9_-]*/static/ {
        proxy_cache_valid 200 302 60m;
        proxy_cache_valid 404 1m;
        proxy_buffering on;
        expires 864000;
        proxy_pass http://localhost:8069;
    }

    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/www.leewise.in/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/www.leewise.in/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot

}

server {
    listen 80;
    server_name www.leewise.in;
    return 301 https://$host$request_uri; # Redirect HTTP to HTTPS
}
EOL

# Enable leewise Nginx config
sudo ln -s /etc/nginx/sites-available/leewise.conf /etc/nginx/sites-enabled/leewise.conf
sudo nginx -t
sudo service nginx restart

# Create Leewise service file
sudo nano /etc/systemd/system/leewise.service
cat <<EOL | sudo tee /etc/systemd/system/leewise.service
[Unit]
Description=Leewise Service
Requires=postgresql.service
After=network.target

[Service]
User=ubuntu
Group=ubuntu
WorkingDirectory=/home/
ExecStart=/home/ubuntu/venv/bin/python3 /home/ubuntu/leewise/leewise-bin -c /home/ubuntu/leewise/debian/leewise.conf
Restart=always

[Install]
WantedBy=multi-user.target
EOL




#!/bin/bash

# Define the pg_hba.conf file path
PG_HBA_PATH="/etc/postgresql/16/main/pg_hba.conf"

# Backup the original pg_hba.conf file
sudo cp $PG_HBA_PATH $PG_HBA_PATH.bak

# Overwrite the pg_hba.conf file with the new content
sudo tee $PG_HBA_PATH > /dev/null <<EOL
# PostgreSQL Client Authentication Configuration File
# ===================================================
#
# Refer to the "Client Authentication" section in the PostgreSQL
# documentation for a complete description of this file.  A short
# synopsis follows.
#
# This file controls: which hosts are allowed to connect, how clients
# are authenticated, which PostgreSQL user names they can use, which
# databases they can access.  Records take one of these forms:
#
# local         DATABASE  USER  METHOD  [OPTIONS]
# host          DATABASE  USER  ADDRESS  METHOD  [OPTIONS]
# hostssl       DATABASE  USER  ADDRESS  METHOD  [OPTIONS]
# hostnossl     DATABASE  USER  ADDRESS  METHOD  [OPTIONS]
# hostgssenc    DATABASE  USER  ADDRESS  METHOD  [OPTIONS]
# hostnogssenc  DATABASE  USER  ADDRESS  METHOD  [OPTIONS]
#
# (The uppercase items must be replaced by actual values.)
#
# The first field is the connection type:
# - "local" is a Unix-domain socket
# - "host" is a TCP/IP socket (encrypted or not)
# - "hostssl" is a TCP/IP socket that is SSL-encrypted
# - "hostnossl" is a TCP/IP socket that is not SSL-encrypted
# - "hostgssenc" is a TCP/IP socket that is GSSAPI-encrypted
# - "hostnogssenc" is a TCP/IP socket that is not GSSAPI-encrypted
#
# DATABASE can be "all", "sameuser", "samerole", "replication", a
# database name, or a comma-separated list thereof. The "all"
# keyword does not match "replication". Access to replication
# must be enabled in a separate record (see example below).
#
# USER can be "all", a user name, a group name prefixed with "+", or a
# comma-separated list thereof.  In both the DATABASE and USER fields
# you can also write a file name prefixed with "@" to include names
# from a separate file.
#
# ADDRESS specifies the set of hosts the record matches.  It can be a
# host name, or it is made up of an IP address and a CIDR mask that is
# an integer (between 0 and 32 (IPv4) or 128 (IPv6) inclusive) that
# specifies the number of significant bits in the mask.  A host name
# that starts with a dot (.) matches a suffix of the actual host name.
# Alternatively, you can write an IP address and netmask in separate
# columns to specify the set of hosts.  Instead of a CIDR-address, you
# can write "samehost" to match any of the server's own IP addresses,
# or "samenet" to match any address in any subnet that the server is
# directly connected to.
#
# METHOD can be "trust", "reject", "md5", "password", "scram-sha-256",
# "gss", "sspi", "ident", "peer", "pam", "ldap", "radius" or "cert".
# Note that "password" sends passwords in clear text; "md5" or
# "scram-sha-256" are preferred since they send encrypted passwords.
#
# OPTIONS are a set of options for the authentication in the format
# NAME=VALUE.  The available options depend on the different
# authentication methods -- refer to the "Client Authentication"
# section in the documentation for a list of which options are
# available for which authentication methods.
#
# Database and user names containing spaces, commas, quotes and other
# special characters must be quoted.  Quoting one of the keywords
# "all", "sameuser", "samerole" or "replication" makes the name lose
# its special character, and just match a database or username with
# that name.
#
# This file is read on server startup and when the server receives a
# SIGHUP signal.  If you edit the file on a running system, you have to
# SIGHUP the server for the changes to take effect, run "pg_ctl reload",
# or execute "SELECT pg_reload_conf()".
#
# Put your actual configuration here
# ----------------------------------
#
# If you want to allow non-local connections, you need to add more
# "host" records.  In that case you will also need to make PostgreSQL
# listen on a non-local interface via the listen_addresses
# configuration parameter, or via the -i or -h command line switches.




# DO NOT DISABLE!
# If you change this first entry you will need to make sure that the
# database superuser can access the database using some other method.
# Noninteractive access to all databases is required during automatic
# maintenance (custom daily cronjobs, replication, and similar tasks).
#
# Database administrative login by Unix domain socket
local   all             postgres                                peer

# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" is for Unix domain socket connections only
local   all             all                                     trust
# IPv4 local connections:
host    all             all             127.0.0.1/32            scram-sha-256
# IPv6 local connections:
host    all             all             ::1/128                 scram-sha-256
# Allow replication connections from localhost, by a user with the
# replication privilege.
local   replication     all                                     peer
host    replication     all             127.0.0.1/32            scram-sha-256
host    replication     all             ::1/128                 scram-sha-256
EOL

# Restart PostgreSQL to apply changes
sudo systemctl restart postgresql

echo "pg_hba.conf has been updated and PostgreSQL restarted."



# Install Certbot for SSL
sudo apt install certbot python3-certbot-nginx -y
sudo certbot --nginx -d www.leewise.in

# Reload systemd, enable, start and restart the service
sudo systemctl daemon-reload
sudo systemctl enable leewise.service
sudo systemctl start leewise.service
sudo systemctl restart nginx
sudo systemctl status leewise.service