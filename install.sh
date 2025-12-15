#!/bin/sh
# ============================================================
# Project: rpi5-zerotier-bridge
# Baseline: rpi5-zerotier-bridge Baseline 1.0.6 (Path Fix)
# ============================================================

set -euo pipefail

# --- Variables ---
BASELINE_NAME="rpi5-zerotier-bridge"
BASELINE_VERSION="1.0.6"
ZT_NETWORK_ID="" 
LOG_FILE="/tmp/zt-install.log"

# --- Logging Helper ---
log() {
    echo "[$BASELINE_NAME] $1" | tee -a "$LOG_FILE"
}

# --- Root Check ---
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi

echo "▶ Deploying $BASELINE_NAME Baseline $BASELINE_VERSION"

# --- 1. User Input (Network ID) ---
if [ -z "$ZT_NETWORK_ID" ]; then
    echo ""
    echo -n "Enter your ZeroTier Network ID (16 chars): "
    read -r input_id < /dev/tty
    ZT_NETWORK_ID=$(echo "$input_id" | tr -cd 'a-zA-Z0-9')
    echo "   > Detected ID: $ZT_NETWORK_ID"
fi

if [ ${#ZT_NETWORK_ID} -ne 16 ]; then
    log "Error: Network ID must be exactly 16 characters."
    exit 1
fi

# --- 2. Install Packages ---
log "Updating package lists..."
opkg update > /dev/null 2>&1 || log "Warning: opkg update failed, trying to proceed..."

log "Installing ZeroTier..."
if ! opkg list-installed | grep -q zerotier; then
    opkg install zerotier
else
    log "ZeroTier already installed."
fi

# --- 3. Configure ZeroTier (Standard Naming) ---
log "Configuring ZeroTier..."

# Find the binary dynamically
ZT_BIN=$(command -v zerotier-one)
if [ -z "$ZT_BIN" ]; then
    log "CRITICAL: zerotier-one binary not found in path!"
    log "Attempting to locate..."
    ZT_BIN=$(find /usr -name zerotier-one | head -n 1)
    if [ -z "$ZT_BIN" ]; then
        log "Error: Could not find zerotier-one binary. Installation failed."
        exit 1
    fi
fi
log "Binary located at: $ZT_BIN"

# Wipe existing config
rm -f /etc/config/zerotier
touch /etc/config/zerotier

# Build Config using standard 'zerotier' section name
uci batch <<EOF
set zerotier.zerotier=zerotier
set zerotier.zerotier.enabled='1'
add_list zerotier.zerotier.join_list='$ZT_NETWORK_ID'
commit zerotier
EOF

log "Config rebuilt."

# reload procd to ensure it sees the new config
/etc/init.d/zerotier disable
/etc/init.d/zerotier enable

log "Starting Service..."
if ! /etc/init.d/zerotier restart; then
    log "Warning: Standard restart failed. Trying manual daemon start..."
    $ZT_BIN -d
fi

log "Waiting for ZeroTier to initialize (10s)..."
sleep 10

# --- 4. Join Network & Get Interface ---
log "Ensuring network join..."

# Check if running
if ! pgrep -x "zerotier-one" > /dev/null; then
    log "Service NOT running. Attempting force start..."
    $ZT_BIN -d
    sleep 5
fi

# Force join
zerotier-cli join "$ZT_NETWORK_ID" || true

log "Waiting for interface assignment..."
ZT_DEV=""
MAX_RETRIES=20
COUNT=0

while [ $COUNT -lt $MAX_RETRIES ]; do
    ZT_DEV=$(zerotier-cli listnetworks | grep "$ZT_NETWORK_ID" | awk '{print $8}')
    if [ -n "$ZT_DEV" ] && [ "$ZT_DEV" != "-" ]; then
        log "Found ZeroTier interface: $ZT_DEV"
        break
    fi
    sleep 2
    COUNT=$((COUNT+1))
    echo -n "."
done

echo ""

if [ -z "$ZT_DEV" ] || [ "$ZT_DEV" = "-" ]; then
    log "Error: Could not determine ZeroTier interface name."
    log "Status: $(zerotier-cli listnetworks)"
    exit 1
fi

# --- 5. Bridge Configuration ---
log "Updating Network Bridge (br-lan)..."

BR_NAME=$(uci -q get network.@device[0].name)
if [ "$BR_NAME" != "br-lan" ]; then
    log "Warning: First network device is not br-lan. Scanning..."
    log "Aborting bridge modification for safety. Please bridge $ZT_DEV manually."
    exit 0
fi

CURRENT_PORTS=$(uci -q get network.@device[0].ports || echo "")

if echo "$CURRENT_PORTS" | grep -q "$ZT_DEV"; then
    log "Interface $ZT_DEV is already in br-lan ports."
else
    log "Adding $ZT_DEV to br-lan ports..."
    uci add_list network.@device[0].ports="$ZT_DEV"
    uci commit network
    
    log "Reloading network..."
    /etc/init.d/network reload
fi

# --- 6. Done ---
log "Done."
echo "-------------------------------------------------------"
echo "  Network:  $ZT_NETWORK_ID"
echo "  Device:   $ZT_DEV"
echo "  Identity: $(zerotier-cli info | awk '{print $3}')"
echo "-------------------------------------------------------"
echo "IMPORTANT: Go to my.zerotier.com and ENABLE 'Ethernet Bridging' for this member!"
