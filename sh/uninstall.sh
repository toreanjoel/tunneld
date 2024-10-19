#!/bin/bash

echo "Stopping services (dnsmasq, hostapd)..."
sudo systemctl stop dnsmasq
sudo systemctl stop hostapd

# Remove services from startup
echo "Disabling services from startup..."
sudo systemctl disable dnsmasq
sudo systemctl disable hostapd

# Remove the configuration files
echo "Removing configuration files for dnsmasq, hostapd, and app..."
sudo rm -f /etc/dnsmasq.conf
sudo rm -f /etc/dnsmasq.blacklist
sudo rm -f /etc/hostapd/hostapd.conf

# Remove the app directory
echo "Removing the Elixir application..."
sudo rm -rf /home/pi/sentinel

# Remove Elixir, Erlang, and ASDF (optional)
read -p "Do you want to remove Elixir, Erlang, and ASDF? (y/n): " remove_lang
if [ "$remove_lang" == "y" ]; then
  # Remove ASDF and installed versions
  rm -rf ~/.asdf
  sed -i '/asdf.sh/d' ~/.bashrc
  sed -i '/asdf.bash/d' ~/.bashrc
  source ~/.bashrc
  echo "ASDF and installed versions removed."
fi

# Remove system modifications
echo "Removing static IP configuration..."
sudo sed -i '/interface eth0/d' /etc/dhcpcd.conf
sudo sed -i '/static ip_address/d' /etc/dhcpcd.conf
sudo sed -i '/static routers/d' /etc/dhcpcd.conf
sudo sed -i '/static domain_name_servers/d' /etc/dhcpcd.conf
sudo systemctl restart dhcpcd

echo "Uninstallation complete!"
