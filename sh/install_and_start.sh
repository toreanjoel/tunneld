#!/bin/bash

# Update system packages
echo "Updating system packages..."
sudo apt-get update

# Install necessary system packages
echo "Installing required system packages (dnsmasq, hostapd, git, curl)..."
sudo apt-get install -y dnsmasq hostapd git curl

# Install Elixir and Phoenix dependencies
echo "Installing Elixir..."
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
sudo dpkg -i erlang-solutions_2.0_all.deb
sudo apt-get update
sudo apt-get install -y esl-erlang elixir

# Install Phoenix framework
echo "Installing Phoenix framework..."
mix local.hex --force
mix archive.install hex phx_new --force

# Install the project and deps
echo "Starting project setup..."
cd ./

# Fetch Elixir project dependencies
echo "Fetching dependencies for Elixir project..."
mix deps.get

# Set up Wi-Fi access point (hostapd)
echo "Setting up hostapd configuration..."
sudo cp ./configs/hostapd.conf /etc/hostapd/hostapd.conf
sudo systemctl enable hostapd

# Set up DNS/DHCP server (dnsmasq)
echo "Setting up dnsmasq configuration..."
sudo cp ./configs/dnsmasq.conf /etc/dnsmasq.conf
sudo cp ./configs/dnsmasq.blacklist /etc/dnsmasq.blacklist
sudo systemctl enable dnsmasq

# Set up static IP for Ethernet (eth0)
echo "Configuring static IP for Ethernet..."
sudo bash -c 'echo "
interface eth0
static ip_address=192.168.1.100/24
static routers=192.168.1.1
static domain_name_servers=8.8.8.8" >> /etc/dhcpcd.conf'
sudo systemctl restart dhcpcd

# Start dnsmasq and hostapd services
echo "Starting dnsmasq and hostapd services..."
sudo systemctl restart dnsmasq
sudo systemctl restart hostapd

# Generate a UUID for this device and store it in a config file
echo "Generating UUID for this device..."
uuid=$(uuidgen)
echo $uuid > ./configs/device_uuid.txt

# Start the Phoenix app manually in the background
echo "Starting Phoenix app..."
MIX_ENV=prod mix phx.server &

echo "Installation and setup complete!"
