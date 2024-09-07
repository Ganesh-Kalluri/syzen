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

# Install PostgreSQL and set up the user
sudo apt install -y postgresql postgresql-client
sudo -u postgres psql -c "CREATE USER leewise WITH SUPERUSER CREATEDB CREATEROLE LOGIN;"

# Set up the virtual environment and install dependencies
python3.10 -m venv ~/venv
source ~/venv/bin/activate
cd leewise
sudo apt install -y python3-pip libldap2-dev libpq-dev libsasl2-dev
pip install pyjwt
sudo apt install wkhtmltopdf
python3.10 -m pip install -r requirements.txt

# Open port for Odoo
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 8069 -j ACCEPT

# Nginx setup
sudo apt install nginx -y

# Remove default site configs
sudo rm /etc/nginx/sites-enabled/default
sudo rm /etc/nginx/sites-available/default

# Create leewise Nginx config
cat <<EOL | sudo tee /etc/nginx/sites-available/leewise.conf
server {
   listen 80;
   server_name www.leewise.in;

   proxy_set_header X-Forwarded-Host \$host;
   proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
   proxy_set_header X-Forwarded-Proto \$scheme;
   proxy_set_header X-Real-IP \$remote_addr;
   add_header X-Frame-Options "SAMEORIGIN";
   add_header X-XSS-Protection "1; mode=block";
   proxy_set_header X-Client-IP \$remote_addr;
   proxy_set_header HTTP_X_FORWARDED_HOST \$remote_addr;

   access_log  /var/log/nginx/leewise-access.log;
   error_log   /var/log/nginx/leewise-error.log;

   proxy_buffers   16 64k;
   proxy_buffer_size   128k;

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
   gzip_buffers    4 32k;
   gzip_types  text/css text/less text/plain text/xml application/xml application/json application/javascript application/pdf image/jpeg image/png;
   gzip_vary   on;
   client_header_buffer_size 4k;
   large_client_header_buffers 4 64k;
   client_max_body_size 0;

   location / {
      proxy_pass http://127.0.0.1:8069;
      proxy_redirect off;
   }

   location /longpolling {
      proxy_pass http://127.0.0.1:8072;
   }

   location ~* .(js|css|png|jpg|jpeg|gif|ico)$ {
      expires 2d;
      proxy_pass http://127.0.0.1:8069;
      add_header Cache-Control "public, no-transform";
   }

   location ~ /[a-zA-Z0-9_-]*/static/ {
      proxy_cache_valid 200 302 60m;
      proxy_cache_valid 404      1m;
      proxy_buffering    on;
      expires 864000;
      proxy_pass http://127.0.0.1:8069;
   }
}
EOL

# Enable leewise Nginx config
sudo ln -s /etc/nginx/sites-available/leewise.conf /etc/nginx/sites-enabled/leewise.conf
sudo nginx -t
sudo service nginx restart

# Run leewise with the specified config file
python3.10 leewise-bin -c debian/leewise.conf
