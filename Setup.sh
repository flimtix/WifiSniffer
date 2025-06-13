#!/bin/bash

# =======================
# Wifi Sniffer Setup
# 
# Documentation:
# This script should configure the sytem for the wifi sniffing.
# It will create a access point (hostapd) with a dhcp and dns server (dnsmasq).
# You need two network cards. One with a ethernet connection to the internet and one for the access point.
# For the ethernet connection you can connect your phone via USB.    
#
#
# How to use the script:
# sudo ./Setup.sh              → setup and run everything
# sudo ./Setup.sh status       → show status and info
# sudo ./Setup.sh cleanup      → revert/cleanup everything
# sudo ./Setup.sh dryrun       → just simulate, do not change system
# sudo ./Setup.sh install      → install all needed packages
#
#
# Docs that could maybe be useful:
# https://wireless.docs.kernel.org/en/latest/en/users/documentation/hostapd.html
# https://docs.silabs.com/wifi91xrcp/2.10.1/wifi91xrcp-developers-guide-wifi-configuration/ap-parameters
# https://gist.github.com/aureeaubert/0cf6a91556b7eceeaaef6e5c998362e1
# =======================


# ========================
# Configurable Variables
# ========================

WLAN_IF="wlan0"
LAN_IF="eth0"
WLAN_IP="10.0.0.1"
WLAN_NETMASK="255.255.255.0"
DHCP_RANGE_START="10.0.0.10"
DHCP_RANGE_END="10.0.0.250"
SSID_NAME="WifiTest"
CHANNEL="1"
LOG_FILE="/var/log/dnsmasq.log"
SCRIPT_LOG="/var/log/wlan_demo_script.log"
HOSTAPD_CONF="/etc/hostapd/hostapd.conf"
DNSMASQ_CONF="/etc/dnsmasq.conf"
BACKUP_DIR="/root/wlan_demo_backup"

# ========================
# Colours for Output
# ========================
NC='\033[0m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
RED='\033[1;31m'
YELLOW='\033[1;33m'

function info()    { echo -e "${GREEN}[INFO]${NC} $1" | tee -a $SCRIPT_LOG; }
function error()   { echo -e "${RED}[ERROR]${NC} $1" | tee -a $SCRIPT_LOG; }
function warn()    { echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a $SCRIPT_LOG; }
function success() { echo -e "${BLUE}[OK]${NC} $1" | tee -a $SCRIPT_LOG; }

# ========================
# Root privilege check
# ========================
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (or with sudo)."
    exit 1
fi

mkdir -p $BACKUP_DIR

# ========================
# Interface Check
# ========================
check_interfaces() {
    info "Checking network interfaces..."

    if ! ip link show $WLAN_IF > /dev/null 2>&1; then
        error "Wireless interface $WLAN_IF does not exist! Please set the correct interface."
        exit 1
    fi

    if ! ip link show $LAN_IF > /dev/null 2>&1; then
        error "LAN interface $LAN_IF does not exist! Please set the correct interface."
        exit 1
    fi

    if ! ip link show $WLAN_IF | grep -q "UP"; then
        warn "$WLAN_IF is not UP. Trying to bring it up..."
        ip link set $WLAN_IF up
        sleep 1
        if ! ip link show $WLAN_IF | grep -q "UP"; then
            error "Failed to bring up $WLAN_IF."
            exit 1
        fi
    fi

    if ! ip link show $LAN_IF | grep -q "UP"; then
        warn "$LAN_IF is not UP. Trying to bring it up..."
        ip link set $LAN_IF up
        sleep 1
        if ! ip link show $LAN_IF | grep -q "UP"; then
            error "Failed to bring up $LAN_IF."
            exit 1
        fi
    fi

    success "Both network interfaces are present and up."
}

# ========================
# Backup & Restore Functions
# ========================
backup_configs() {
    info "Backing up existing configurations..."
    [[ -f $HOSTAPD_CONF ]] && cp $HOSTAPD_CONF $BACKUP_DIR/hostapd.conf.bak
    [[ -f $DNSMASQ_CONF ]] && cp $DNSMASQ_CONF $BACKUP_DIR/dnsmasq.conf.bak
    [[ -f /etc/sysctl.conf ]] && cp /etc/sysctl.conf $BACKUP_DIR/sysctl.conf.bak
    [[ -f $LOG_FILE ]] && cp $LOG_FILE $BACKUP_DIR/dnsmasq.log.bak
    success "Backups created in $BACKUP_DIR."
}

restore_configs() {
    info "Restoring previous configurations..."
    [[ -f $BACKUP_DIR/hostapd.conf.bak ]] && cp $BACKUP_DIR/hostapd.conf.bak $HOSTAPD_CONF
    [[ -f $BACKUP_DIR/dnsmasq.conf.bak ]] && cp $BACKUP_DIR/dnsmasq.conf.bak $DNSMASQ_CONF
    [[ -f $BACKUP_DIR/sysctl.conf.bak ]] && cp $BACKUP_DIR/sysctl.conf.bak /etc/sysctl.conf
    [[ -f $BACKUP_DIR/dnsmasq.log.bak ]] && cp $BACKUP_DIR/dnsmasq.log.bak $LOG_FILE
    success "Previous configurations restored."
}

# ========================
# Cleanup Function
# ========================
cleanup() {
    info "Stopping hostapd and dnsmasq..."
    systemctl stop hostapd
    systemctl stop dnsmasq

    info "Flushing iptables..."
    iptables -F
    iptables -t nat -F

    info "Disabling IP-Forwarding..."
    sysctl -w net.ipv4.ip_forward=0
    sed -i '/^net.ipv4.ip_forward/ d' /etc/sysctl.conf

    info "Resetting $WLAN_IF..."
    ip addr flush dev $WLAN_IF

    restore_configs

    success "Demo environment fully cleaned up."
    exit 0
}

# ========================
# Status Function
# ========================
status() {
    echo -e "\n${BLUE}--- WLAN Demo Status ---${NC}"
    echo -e "${GREEN}WLAN Interface:$NC $WLAN_IF"
    ip addr show $WLAN_IF | grep inet | grep -v inet6
    echo -e "${GREEN}LAN Interface:$NC $LAN_IF"
    ip addr show $LAN_IF | grep inet | grep -v inet6

    echo -e "${GREEN}hostapd:${NC} $(systemctl is-active hostapd)"
    echo -e "${GREEN}dnsmasq:${NC} $(systemctl is-active dnsmasq)"
    echo -e "${GREEN}IP-Forwarding:${NC} $(sysctl net.ipv4.ip_forward | awk '{print $3}')"
    echo -e "${GREEN}iptables NAT Rule:${NC}"
    iptables -t nat -L POSTROUTING -n -v | grep MASQUERADE
    echo -e "${GREEN}Recent DNS queries:${NC}"
    tail -5 $LOG_FILE 2>/dev/null
    echo -e "${BLUE}------------------------${NC}\n"
    exit 0
}

# ========================
# Internet Connectivity Test
# ========================
test_internet() {
    info "Testing Internet connectivity via $LAN_IF (ping to 8.8.8.8)..."
    ping -I $LAN_IF -c 2 -W 2 8.8.8.8 >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        success "Internet connection is active."
    else
        warn "No Internet connectivity via $LAN_IF!"
    fi
}

# ========================
# Dry Run Option
# ========================
if [[ "$1" == "dryrun" ]]; then
    info "Simulation (dry-run) started..."
    echo "Would set the following settings:"
    echo "  WLAN_IF=$WLAN_IF"
    echo "  LAN_IF=$LAN_IF"
    echo "  WLAN_IP=$WLAN_IP"
    echo "  SSID_NAME=$SSID_NAME"
    echo "  CHANNEL=$CHANNEL"
    echo "  DHCP_RANGE: $DHCP_RANGE_START - $DHCP_RANGE_END"
    echo "No changes made to the system."
    exit 0
fi

# ========================
# Installation
# ========================
if [[ "$1" == "install" ]]; then
    info "Installing required packages (hostapd, dnsmasq, iptables)..."
    apt-get update && apt-get install -y hostapd dnsmasq iptables
    success "Packages installed."
    exit 0
fi

# ========================
# Start/Stop/Status
# ========================
if [[ "$1" == "stop" || "$1" == "cleanup" ]]; then
    cleanup
elif [[ "$1" == "status" ]]; then
    status
fi

# ========================
# Begin Demo Setup
# ========================
echo "" > $SCRIPT_LOG
info "Starting demo network setup..."

check_interfaces
backup_configs
test_internet

# Stop running services
systemctl stop NetworkManager
systemctl stop wpa_supplicant

# Stop hostapd and dnsmasq
systemctl stop hostapd
systemctl stop dnsmasq


# Set WLAN interface to Managed/AP mode
info "Setting $WLAN_IF to monitor/AP mode..."
ip link set $WLAN_IF down
iwconfig $WLAN_IF mode monitor
ip link set $WLAN_IF up
sleep 2
if ip a | grep "$WLAN_IF" | grep "state UP" > /dev/null; then
    success "$WLAN_IF is up."
else
    error "$WLAN_IF could not be brought up!"; exit 1
fi

# Assign static IP to WLAN interface
info "Assigning static IP $WLAN_IP to $WLAN_IF..."
ip addr flush dev $WLAN_IF
ip addr add $WLAN_IP/24 dev $WLAN_IF
sleep 1
if ip addr show $WLAN_IF | grep "$WLAN_IP" > /dev/null; then
    success "Static IP assigned."
else
    error "Static IP assignment failed!"; exit 1
fi

# hostapd config
info "Creating hostapd configuration..."
cat > $HOSTAPD_CONF <<EOF
interface=$WLAN_IF
driver=nl80211
ssid=$SSID_NAME
hw_mode=g
channel=$CHANNEL
EOF
success "hostapd configuration written."

# dnsmasq config
info "Creating dnsmasq configuration..."
cat > $DNSMASQ_CONF <<EOF
interface=$WLAN_IF
dhcp-range=$DHCP_RANGE_START,$DHCP_RANGE_END,12h
dhcp-option=3,$WLAN_IP
dhcp-option=6,$WLAN_IP
log-queries
log-facility=$LOG_FILE
EOF

touch $LOG_FILE
chmod 644 $LOG_FILE
success "dnsmasq configuration written."

# Enable IP-Forwarding
info "Enabling IP-Forwarding..."
sysctl -w net.ipv4.ip_forward=1
sed -i '/^net.ipv4.ip_forward/ d' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
success "IP-Forwarding enabled."

# iptables NAT
info "Setting iptables rules for NAT..."
iptables -t nat -F
iptables -F
iptables -t nat -A POSTROUTING -o $LAN_IF -j MASQUERADE
iptables -A FORWARD -i $WLAN_IF -o $LAN_IF -j ACCEPT
iptables -A FORWARD -i $LAN_IF -o $WLAN_IF -m state --state ESTABLISHED,RELATED -j ACCEPT
success "iptables rules set."

# Start hostapd
info "Starting hostapd..."
systemctl unmask hostapd
systemctl enable hostapd
systemctl restart hostapd
sleep 2
if pgrep hostapd > /dev/null; then
    success "hostapd is running."
else
    error "hostapd could not be started!"; exit 1
fi

# Start dnsmasq
info "Starting dnsmasq..."
systemctl enable dnsmasq
systemctl restart dnsmasq
sleep 2
if pgrep dnsmasq > /dev/null; then
    success "dnsmasq is running."
else
    error "dnsmasq could not be started!"; exit 1
fi

# Automatic Internet Test
ping -c 2 -W 2 8.8.8.8 >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
    success "Internet test: Success."
else
    warn "Internet test: Failed!"
fi

# Show overview
status

# Show live DNS monitoring hint
info "To watch live DNS queries, use:"
echo -e "${BLUE}    sudo tail -f $LOG_FILE | grep query${NC}"

success "All steps completed successfully!"

exit 0

