#!/bin/bash

# Function to prompt user for input with a default value
prompt_with_default() {
    local prompt_text="$1"
    local default_value="$2"
    local user_input

    read -p "$prompt_text [$default_value]: " user_input
    echo "${user_input:-$default_value}"
}

# Step 0: Set the locale to prevent locale-related warnings (before updating packages)
echo "Configuring locale settings..."
sudo sed -i 's/^# *en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/' /etc/locale.gen
sudo locale-gen
sudo update-locale LANG=en_GB.UTF-8
export LANG=en_GB.UTF-8
export LANGUAGE=en_GB.UTF-8
export LC_ALL=en_GB.UTF-8

# Step 1: Update system packages
echo "Updating system packages..."
sudo apt-get update -y

# Step 2: Install necessary packages like dnsmasq, hostapd, git, curl, and uuidgen
echo "Installing required system packages (dnsmasq, hostapd, git, curl, uuidgen)..."
sudo apt-get install -y dnsmasq hostapd git curl util-linux automake autoconf \
libreadline-dev libncurses-dev libssl-dev libyaml-dev libxslt-dev libffi-dev \
libtool unixodbc-dev unzip

# Step 3: Install ASDF Version Manager
echo "Installing ASDF Version Manager..."
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.11.3

# Add ASDF to shell
echo 'source ~/.asdf/asdf.sh' >> ~/.bashrc
echo 'source ~/.asdf/completions/asdf.bash' >> ~/.bashrc
source ~/.bashrc

# Step 4: Install Erlang and Elixir via ASDF
echo "Installing Erlang and Elixir via ASDF..."

# Install Erlang plugin
asdf plugin-add erlang https://github.com/asdf-vm/asdf-erlang.git

# Install Elixir plugin
asdf plugin-add elixir https://github.com/asdf-vm/asdf-elixir.git

# Install Erlang (choose a compatible version with Elixir 1.16)
ERLANG_VERSION="25.0"
echo "Installing Erlang $ERLANG_VERSION..."
asdf install erlang $ERLANG_VERSION
asdf global erlang $ERLANG_VERSION

# Install Elixir 1.16.0
ELIXIR_VERSION="1.16.0"
echo "Installing Elixir $ELIXIR_VERSION..."
asdf install elixir $ELIXIR_VERSION
asdf global elixir $ELIXIR_VERSION

# Step 5: Install Phoenix (if needed)
# If you need Phoenix framework, you can install it using the following commands.
# Uncomment the lines below if you wish to install Phoenix.

# echo "Installing Phoenix framework..."
# mix local.hex --force
# mix archive.install hex phx_new --force

# Step 6: Fetch Elixir project dependencies
# Ensure you're in the project directory before running mix commands
echo "Installing dependencies for Elixir project..."
cd /home/pi/sentinel || { echo "Project directory /home/pi/sentinel not found."; exit 1; }
mix deps.get

# Step 7: Prompt user for Wi-Fi access point details (AP)
ssid=$(prompt_with_default "Enter the SSID (Wi-Fi network name) for your access point" "YourNetworkSSID")
password=$(prompt_with_default "Enter the password for your Wi-Fi access point" "YourSecurePassword")
channel=$(prompt_with_default "Enter the Wi-Fi channel (1, 6, or 11 recommended for 2.4GHz networks)" "7")

# Step 8: Prompt user for network configuration
gateway_ip=$(prompt_with_default "Enter the gateway IP for your router (usually 192.168.1.1 or 192.168.0.1)" "192.168.1.1")
static_ip=$(prompt_with_default "Enter the static IP for this device (this Raspberry Pi)" "192.168.3.58")
dns_server=$(prompt_with_default "Enter the DNS server (e.g., 8.8.8.8 for Google DNS)" "1.1.1.1")

# Step 9: Setup directories for blacklist and logs inside the project directory
echo "Setting up project directories for logs and configs..."
mkdir -p /home/pi/sentinel/logs
mkdir -p /home/pi/sentinel/data

# Step 10: Setup hostapd (Wi-Fi access point)
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
rsn_pairwise=CCMP
EOF

# Enable hostapd configuration
sudo sed -i 's|#DAEMON_CONF="|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

# Step 11: Setup dnsmasq (DNS and DHCP server)
echo "Backing up existing dnsmasq configuration..."
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.backup

echo "Setting up dnsmasq configuration..."
sudo bash -c "cat > /etc/dnsmasq.conf" <<EOF
interface=wlan0
bind-interfaces
server=$dns_server
domain-needed
bogus-priv
dhcp-range=192.168.4.10,192.168.4.100,12h  # IP address range for connected devices
log-queries
log-facility=/home/pi/sentinel/data/dnsmasq.log
conf-file=/home/pi/sentinel/data/dnsmasq.blacklist  # Blacklist file location
cache-size=1000
EOF

# Step 12: Set a static IP for the Ethernet interface (eth0)
echo "Configuring static IP for Ethernet..."
sudo bash -c "cat >> /etc/dhcpcd.conf" <<EOF

interface eth0
static ip_address=$static_ip/24
static routers=$gateway_ip
static domain_name_servers=$dns_server
EOF

# Restart the dhcpcd service to apply the static IP configuration.
sudo systemctl restart dhcpcd

# Step 13: Setup dnsmasq blacklist
echo "Setting up blacklist for dnsmasq..."
sudo touch /home/pi/sentinel/data/dnsmasq.blacklist

# Step 14: Start dnsmasq and hostapd services
echo "Starting dnsmasq and hostapd..."
sudo systemctl unmask hostapd
sudo systemctl enable hostapd
sudo systemctl restart hostapd
sudo systemctl enable dnsmasq
sudo systemctl restart dnsmasq

# Wait for a little bit to ensure dnsmasq is ready
sleep 5
sudo systemctl restart hostapd
sudo systemctl restart dnsmasq.service

# Step 15: Start the Phoenix app manually (if applicable)
# If you have a Phoenix app to start, you can start it here. Since you mentioned not to add Phoenix logs, we'll skip this step.

# echo "Starting Phoenix app..."
# cd /home/pi/sentinel
# MIX_ENV=prod mix phx.server &

# Display important log file and configuration details to the user
echo "Installation and setup complete!"
echo "------------------------------------------------------"
echo "Access the dashboard via your browser at http://$static_ip"
echo ""
echo "Blacklist location: /home/pi/sentinel/data/dnsmasq.blacklist"
echo "DNSMasq log file: /home/pi/sentinel/data/dnsmasq.log"
echo "Elixir and Erlang installed via ASDF."
