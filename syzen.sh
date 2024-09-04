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
wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
sudo apt-get update
sudo apt-get install -y postgresql-16 postgresql-client-16
sudo -u postgres psql -c "CREATE USER leewise WITH SUPERUSER CREATEDB CREATEROLE LOGIN;"

# Set up the virtual environment and install dependencies
python3.10 -m venv ~/venv
source ~/venv/bin/activate
cd leewise
sudo apt install -y python3-pip libldap2-dev libpq-dev libsasl2-dev
sudo apt-get install wkhtmltopdf
pip install pyjwt
python3.10 -m pip install -r requirements.txt

# Run leewise with the specified config file
python3.10 leewise-bin -c debian/leewise.conf
