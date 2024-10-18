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
echo "Configuring locale settings..."
sudo sed -i 's/^# *en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/' /etc/locale.gen
sudo locale-gen
sudo update-locale LANG=en_GB.UTF-8
export LANG=en_GB.UTF-8
export LANGUAGE=en_GB.UTF-8
export LC_ALL=en_GB.UTF-8

# Step 1: Update system packages
echo "Updating system packages..."
sudo apt-get update

# Step 2: Install necessary packages like dnsmasq, hostapd, git, curl, uuidgen, and build dependencies for `asdf`
echo "Installing required system packages (dnsmasq, hostapd, git, curl, uuidgen, build dependencies)..."
sudo apt-get install -y dnsmasq hostapd git curl autoconf build-essential libssl-dev libncurses5-dev

# Step 3: Install `asdf` version manager
echo "Installing asdf version manager..."
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.9.0
echo -e '\n. $HOME/.asdf/asdf.sh' >> ~/.bashrc
echo -e '\n. $HOME/.asdf/completions/asdf.bash' >> ~/.bashrc
source ~/.bashrc

# Step 4: Install Erlang and Elixir using `asdf`
echo "Installing Erlang and Elixir using asdf..."

# Add asdf plugins for Erlang and Elixir
asdf plugin-add erlang https://github.com/asdf-vm/asdf-erlang.git
asdf plugin-add elixir https://github.com/asdf-vm/asdf-elixir.git

# Install the latest stable version of Erlang
asdf install erlang latest
asdf global erlang latest

# Install the latest stable version of Elixir
asdf install elixir latest
asdf global elixir latest

# Verify installation
echo "Verifying Elixir and Erlang installation..."
elixir --version
erl -version

# Step 5: Fetch Elixir project dependencies
echo "Installing dependencies for Elixir project..."
cd /home/pi/sentinel
mix deps.get

# Step 6: Prompt user for Wi-Fi access point details (AP)
ssid=$(prompt_with_default "Enter the SSID (Wi-Fi network name) for your access point" "YourNetworkSSID")
password=$(prompt_with_default "Enter the password for your Wi-Fi access point" "YourSecurePassword")
channel=$(prompt_with_default "Enter the Wi-Fi channel (1, 6, or 11 recommended for 2.4GHz networks)" "7")

# Step 7: Prompt user for network configuration
gateway_ip=$(prompt_with_default "Enter the gateway IP for your router (usually 192.168.1.1 or 192.168.0.1)" "192.168.1.1")
static_ip=$(prompt_with_default "Enter the static IP for this device (this Raspberry Pi)" "192.168.3.58")
dns_server=$(prompt_with_default "Enter the DNS server (e.g., 8.8.8.8 for Google DNS)" "1.1.1.1")

# Step 8: Setup directories for blacklist and logs inside the project directory
echo "Setting up project directories for logs and configs..."
mkdir -p /home/pi/sentinel/logs
mkdir -p /home/pi/sentinel/configs

# Step 9: Setup hostapd (Wi-Fi access point)
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

# Step 10: Setup dnsmasq (DNS and DHCP server)
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

# Step 11: Set a static IP for the Ethernet interface (eth0)
echo "Configuring static IP for Ethernet..."
sudo bash -c 'echo "
interface eth0
static ip_address=$static_ip/24
static routers=$gateway_ip
static domain_name_servers=$dns_server" >> /etc/dhcpcd.conf'

# Restart the dhcpcd service to apply the static IP configuration.
sudo systemctl restart dhcpcd

# Step 12: Setup dnsmasq blacklist
echo "Setting up blacklist for dnsmasq..."
sudo touch /home/pi/sentinel/data/dnsmasq.blacklist

# Step 13: Start dnsmasq and hostapd services
# We restart `hostapd` before `dnsmasq` to ensure that wlan0 is available.
echo "Starting dnsmasq and hostapd..."
sudo systemctl enable hostapd
sudo systemctl restart hostapd
sudo systemctl enable dnsmasq
sudo systemctl restart dnsmasq

# wait for a little bit to ensure dnsmasq is ready
sleep 5
sudo systemctl restart hostapd
sudo systemctl restart dnsmasq.service

# Step 14: Start the Phoenix app manually
echo "Starting Phoenix app..."
cd /home/pi/sentinel
MIX_ENV=prod mix phx.server &

# Display important log file and configuration details to the user
echo "Installation and setup complete!"
echo "------------------------------------------------------"
echo "Access the dashboard via your browser at http://$static_ip"
echo ""
echo "Blacklist location: /home/pi/sentinel/data/dnsmasq.blacklist"
echo "DNSMasq log file: /home/pi/sentinel/data/dnsmasq.log"
echo "Phoenix logs will be available in your app's log folder."
