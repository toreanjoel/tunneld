#!/bin/bash

# Function to prompt user for input with a default value
# This allows the user to provide custom inputs or accept defaults.
prompt_with_default() {
    local prompt_text="$1"
    local default_value="$2"
    local user_input

    read -p "$prompt_text [$default_value]: " user_input
    echo "${user_input:-$default_value}"
}

# **Step 0: Configure Locale Settings**
# Prevents locale-related warnings during package installation.
echo "Configuring locale settings..."
sudo sed -i 's/^# *en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/' /etc/locale.gen
sudo locale-gen
sudo update-locale LANG=en_GB.UTF-8
export LANG=en_GB.UTF-8
export LANGUAGE=en_GB.UTF-8
export LC_ALL=en_GB.UTF-8

# **Step 1: Update System Packages**
echo "Updating system packages..."
sudo apt-get update -y

# **Step 2: Install Required System Packages**
# Installs dnsmasq and hostapd for setting up the access point.
echo "Installing required system packages..."
sudo apt-get install -y dnsmasq hostapd

# **Step 3: Prompt User for Wi-Fi Access Point Details**
ssid=$(prompt_with_default "Enter the SSID (Wi-Fi network name) for your access point" "YourNetworkSSID")
password=$(prompt_with_default "Enter the password for your Wi-Fi access point" "YourSecurePassword")
channel=$(prompt_with_default "Enter the Wi-Fi channel (1, 6, or 11 recommended for 2.4GHz networks)" "6")

# **Step 4: Remove Existing Static IP Configuration for wlan0**
echo "Removing existing static IP configuration for wlan0..."
sudo sed -i '/interface wlan0/,/nohook wpa_supplicant/d' /etc/dhcpcd.conf

# **Configure Static IP for wlan0**
echo "Configuring static IP for wlan0..."
sudo bash -c "cat >> /etc/dhcpcd.conf" <<EOF

interface wlan0
    static ip_address=192.168.4.1/24
    nohook wpa_supplicant
EOF

# **Step 5: Restart dhcpcd Service**
echo "Restarting dhcpcd service..."
sudo systemctl restart dhcpcd
sleep 5  # Wait for the service to restart

# **Step 6: Remove Old hostapd Configuration and Set Up New One**
echo "Setting up hostapd configuration..."
sudo rm -f /etc/hostapd/hostapd.conf
sudo bash -c "cat > /etc/hostapd/hostapd.conf" <<EOF
interface=wlan0
driver=nl80211
ssid=$ssid
hw_mode=g
channel=$channel
wmm_enabled=1
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$password
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

# Point hostapd to the configuration file
echo "Updating /etc/default/hostapd to point to the configuration file..."
sudo sed -i '/^DAEMON_CONF=/d' /etc/default/hostapd
echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' | sudo tee -a /etc/default/hostapd

# **Step 7: Remove Old dnsmasq Configuration and Set Up New One**
echo "Configuring dnsmasq..."
sudo rm -f /etc/dnsmasq.conf
sudo bash -c "cat > /etc/dnsmasq.conf" <<EOF
interface=wlan0      # Use interface wlan0
bind-interfaces      # Bind to the interface
server=1.1.1.1       # Forward DNS requests to Cloudflare DNS
domain-needed        # Don't forward short names
bogus-priv           # Drop the non-routed address spaces
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
EOF

# **Step 8: Enable IP Forwarding**
echo "Enabling IP forwarding..."
sudo sed -i 's|^#net.ipv4.ip_forward=.*|net.ipv4.ip_forward=1|' /etc/sysctl.conf
sudo sysctl -p

# **Step 9: Configure NAT Between wlan0 and eth0**
echo "Configuring NAT between wlan0 and eth0..."
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo sh -c "iptables-save > /etc/iptables.ipv4.nat"

# Since you don't want services running on boot, we won't modify /etc/rc.local.

# **Step 10: Final Message**
echo "--------------------------------------"
echo "Installation and setup complete!"
echo "Your Raspberry Pi is now configured as a Wi-Fi access point."
echo "To start the access point, run the start_services.sh script."
echo "--------------------------------------"
