#!/bin/bash

echo "Stopping services (dnsmasq, hostapd)..."
sudo systemctl stop dnsmasq
sudo systemctl stop hostapd

# **Remove configuration files**

# **Restore default dnsmasq configuration**
echo "Restoring default dnsmasq configuration..."
sudo rm -f /etc/dnsmasq.conf
sudo bash -c "cat > /etc/dnsmasq.conf" <<EOF
# Default dnsmasq configuration.
# You may need to customize this file to suit your needs.
EOF

# **Remove hostapd configuration**
echo "Removing hostapd configuration..."
sudo rm -f /etc/hostapd/hostapd.conf
sudo sed -i '/^DAEMON_CONF=/d' /etc/default/hostapd

# **Remove static IP configuration for wlan0 from /etc/dhcpcd.conf**
echo "Removing static IP configuration for wlan0..."
sudo sed -i '/interface wlan0/,/nohook wpa_supplicant/d' /etc/dhcpcd.conf

# **Restart dhcpcd service**
echo "Restarting dhcpcd service..."
sudo systemctl restart dhcpcd
sleep 5  # Wait for the service to restart

# **Disable IP forwarding**
echo "Disabling IP forwarding..."
sudo sed -i 's|^net.ipv4.ip_forward=1|#net.ipv4.ip_forward=1|' /etc/sysctl.conf
sudo sysctl -p

# **Remove NAT configuration**
echo "Removing NAT configuration..."
sudo iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
sudo rm -f /etc/iptables.ipv4.nat

# **Remove data directories if they were created**
echo "Removing data directories..."
sudo rm -rf /home/pi/sentinel/logs
sudo rm -rf /home/pi/sentinel/data

# **Final Message**
echo "--------------------------------------"
echo "Uninstallation complete!"
echo "Your Raspberry Pi has been restored to its previous network configuration."
echo "--------------------------------------"
