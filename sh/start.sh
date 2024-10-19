#!/bin/bash

# start_services.sh
# Script to start hostapd and dnsmasq services and set up NAT

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit
fi

echo "Starting hostapd and dnsmasq services..."

# **Start Services**
sudo systemctl unmask hostapd
sudo systemctl start hostapd
sudo systemctl start dnsmasq

# **Configure NAT**
echo "Configuring NAT..."
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

echo "Access point started."
