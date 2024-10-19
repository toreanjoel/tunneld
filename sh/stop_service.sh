#!/bin/bash

# stop_service.sh
# Script to stop hostapd and dnsmasq services and clear NAT

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit
fi

echo "Stopping hostapd and dnsmasq services..."

# **Stop Services**
sudo systemctl stop hostapd
sudo systemctl stop dnsmasq

# **Clear NAT**
echo "Clearing NAT rules..."
sudo iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

echo "Access point stopped."
