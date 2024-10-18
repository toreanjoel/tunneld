#!/bin/bash

# Function to prompt user for input with default option
prompt_with_default() {
    local prompt_text="$1"
    local default_value="$2"
    local user_input

    read -p "$prompt_text [$default_value]: " user_input
    echo "${user_input:-$default_value}"
}

# Update system packages
echo "Updating system packages..."
sudo apt-get update

# Install necessary system packages
echo "Installing required system packages (dnsmasq, hostapd, git, curl)..."
sudo apt-get install -y dnsmasq hostapd git curl

# Install Elixir and Phoenix
echo "Installing Elixir..."
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
sudo dpkg -i erlang-solutions_2.0_all.deb
sudo apt-get update
sudo apt-get install -y esl-erlang elixir

# Install Phoenix
echo "Installing Phoenix framework..."
mix local.hex --force
mix archive.install hex phx_new --force

# Clone the project repository
echo "Cloning Project Sentinel from GitHub..."
git clone https://github.com/your_github_username/project_sentinel.git /home/pi/project_sentinel
cd /home/pi/project_sentinel
mix deps.get

# Prompt for Wi-Fi details
ssid=$(prompt_with_default "Enter the SSID for your Wi-Fi access point" "YourNetworkSSID")
password=$(prompt_with_default "Enter the password for your Wi-Fi access point" "YourSecurePassword")
channel=$(prompt_with_default "Enter the Wi-Fi channel (1, 6, or 11 recommended)" "7")

# Prompt for gateway and static IP details
gateway_ip=$(prompt_with_default "Enter the gateway IP for your router" "192.168.1.1")
static_ip=$(prompt_with_default "Enter the static IP for this device (Pi)" "192.168.1.100")
dns_server=$(prompt_with_default "Enter the DNS server (e.g., 8.8.8.8)" "8.8.8.8")

# Setup hostapd configuration
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

# Setup dnsmasq configuration
echo "Setting up dnsmasq configuration..."
sudo bash -c "cat > /etc/dnsmasq.conf" <<EOF
interface=wlan0
bind-interfaces
server=$dns_server
domain-needed
bogus-priv
dhcp-range=192.168.4.10,192.168.4.100,12h
log-queries
log-facility=/var/log/dnsmasq.log
conf-file=/etc/dnsmasq.blacklist
cache-size=1000
EOF

# Setup static IP for Ethernet (eth0)
echo "Configuring static IP for Ethernet..."
sudo bash -c 'echo "
interface eth0
static ip_address=$static_ip/24
static routers=$gateway_ip
static domain_name_servers=$dns_server" >> /etc/dhcpcd.conf'
sudo systemctl restart dhcpcd

# Setup dnsmasq blacklist
echo "Setting up blacklist for dnsmasq..."
sudo touch /etc/dnsmasq.blacklist

# Start services
echo "Starting dnsmasq and hostapd..."
sudo systemctl enable dnsmasq
sudo systemctl enable hostapd
sudo systemctl restart dnsmasq
sudo systemctl restart hostapd

# Generate a UUID for this device
echo "Generating UUID for this device..."
uuid=$(uuidgen)
echo $uuid > ./configs/device_uuid.txt

# Start the Phoenix app manually
echo "Starting Phoenix app..."
MIX_ENV=prod mix phx.server &

echo "Installation and setup complete! Visit your Pi's IP in a browser to access the dashboard."
