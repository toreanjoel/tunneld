#!/bin/bash

# Function to prompt user for input with a default value
# The user can either input a value or hit Enter to use the default option.
prompt_with_default() {
    local prompt_text="$1"
    local default_value="$2"
    local user_input

    read -p "$prompt_text [$default_value]: " user_input
    echo "${user_input:-$default_value}"
}

# Step 0: Set the locale to prevent locale-related warnings (before updating packages)
# This will configure the locale for the Raspberry Pi system.

echo "Configuring locale settings..."
sudo sed -i 's/^# *en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/' /etc/locale.gen
sudo locale-gen
sudo update-locale LANG=en_GB.UTF-8

# Step 1: Update system packages
echo "Updating system packages..."
sudo apt-get update

# Step 2: Install necessary packages like dnsmasq, hostapd, git, and curl
echo "Installing required system packages (dnsmasq, hostapd, git, curl)..."
sudo apt-get install -y dnsmasq hostapd git curl

# Step 3: Install Elixir and Phoenix framework
# This part installs Elixir (necessary for running the Phoenix app).
echo "Installing Elixir..."
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
sudo dpkg -i erlang-solutions_2.0_all.deb
sudo apt-get update
sudo apt-get install -y esl-erlang elixir

# Install Phoenix, which will be the framework for your dashboard
echo "Installing Phoenix framework..."
mix local.hex --force
mix archive.install hex phx_new --force

# Step 4: Fetch Elixir project dependencies
# Once in the project directory, we pull the necessary libraries.
echo "Installing dependencies for Elixir project..."
cd ./
mix deps.get

# Step 5: Prompt user for Wi-Fi access point details (AP)
# Ask the user for SSID, Wi-Fi password, and Wi-Fi channel.
ssid=$(prompt_with_default "Enter the SSID (Wi-Fi network name) for your access point" "YourNetworkSSID")
password=$(prompt_with_default "Enter the password for your Wi-Fi access point" "YourSecurePassword")
channel=$(prompt_with_default "Enter the Wi-Fi channel (1, 6, or 11 recommended for 2.4GHz networks)" "7")

# Step 6: Prompt user for network configuration
# Gateway IP is the IP address of the router the Raspberry Pi will be connected to.
gateway_ip=$(prompt_with_default "Enter the gateway IP for your router (usually 192.168.1.1 or 192.168.0.1)" "192.168.1.1")

# The static IP is the fixed address that the Raspberry Pi will use on the network.
static_ip=$(prompt_with_default "Enter the static IP for this device (this Raspberry Pi)" "192.168.1.100")

# DNS server, typically either the router's IP or a public DNS server like Google's (8.8.8.8).
dns_server=$(prompt_with_default "Enter the DNS server (e.g., 8.8.8.8 for Google DNS)" "8.8.8.8")

# Step 7: Setup hostapd (Wi-Fi access point)
# This part creates the configuration for the Wi-Fi access point, using the SSID, password, and channel the user provided.
echo "Setting up hostapd configuration..."
sudo bash -c "cat > /etc/hostapd/hostapd.conf" <<EOF
interface=wlan0
driver=nl80211
ssid=$ssid
hw_mode=g
channel=$channel
wmm_enabled=1
auth_algs=1
wpa=2
wpa_passphrase=$password
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

# Step 8: Setup dnsmasq (DNS and DHCP server)
# dnsmasq will handle DNS requests and assign IP addresses (via DHCP) to devices connecting to the access point.
# The user will not need to specify the IP range unless they want to change it, so we will hard-code the common range.
echo "Setting up dnsmasq configuration..."
sudo bash -c "cat > /etc/dnsmasq.conf" <<EOF
interface=wlan0
bind-interfaces
server=$dns_server
domain-needed
bogus-priv
dhcp-range=192.168.4.10,192.168.4.100,12h  # IP address range for connected devices
log-queries
log-facility=/var/log/dnsmasq.log
conf-file=/etc/dnsmasq.blacklist  # Blacklist file location
cache-size=1000
EOF

# Step 9: Set a static IP for the Ethernet interface (eth0)
# This ensures the Raspberry Pi has a fixed IP on the network, so it can be accessed easily via its static IP.
echo "Configuring static IP for Ethernet..."
sudo bash -c 'echo "
interface eth0
static ip_address=$static_ip/24
static routers=$gateway_ip
static domain_name_servers=$dns_server" >> /etc/dhcpcd.conf'

# Restart the dhcpcd service to apply the static IP configuration.
sudo systemctl restart dhcpcd

# Step 10: Setup dnsmasq blacklist
# Create the blacklist file for blocking domains.
echo "Setting up blacklist for dnsmasq..."
sudo touch /etc/dnsmasq.blacklist

# Step 11: Start dnsmasq and hostapd services
# This ensures that both dnsmasq and hostapd are started automatically on boot and restarts them now.
echo "Starting dnsmasq and hostapd..."
sudo systemctl enable dnsmasq
sudo systemctl enable hostapd
sudo systemctl restart dnsmasq
sudo systemctl restart hostapd

# Step 12: Generate a UUID for this device
# A unique identifier is created for the Raspberry Pi and stored in the configs folder.
echo "Generating UUID for this device..."
uuid=$(uuidgen)
echo $uuid > ./configs/device_uuid.txt

# Step 13: Start the Phoenix app manually
# This starts the Phoenix server, which will run your web dashboard for real-time management.
echo "Starting Phoenix app..."
MIX_ENV=prod mix phx.server &

echo "Installation and setup complete! Visit your Pi's static IP ($static_ip) in a browser to access the dashboard."
