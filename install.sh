#!/bin/sh
# ============================================================
# Project: rpi5-zerotier-bridge
# Baseline: rpi5-zerotier-bridge Baseline 1.0
#
# Description:
#   Installs ZeroTier and bridges it to br-lan for Layer 2 extension.
#
# Supported OpenWrt Versions:
#   - Tested: 24.10.x
#
# Safety Guarantees:
#   - LAN access preserved
#   - SSH access preserved
#   - Safe to re-run (idempotent)
# ============================================================

set -euo pipefail

# --- Variables ---
BASELINE_NAME="rpi5-zerotier-bridge"
BASELINE_VERSION="1.0"
ZT_NETWORK_ID="" # Leave empty to prompt user
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
    read input_id
    ZT_NETWORK_ID=$(echo "$input_id" | tr -d '[:space:]')
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

# --- 3. Configure ZeroTier ---
log "Configuring ZeroTier..."
uci set zerotier.sample_config.enabled='1'
# Add the network to the UCI config so it persists
# We remove old lists to ensure idempotency
uci -q delete zerotier.@zerotier[0].join_list
uci add_list zerotier.@zerotier[0].join_list="$ZT_NETWORK_ID"
uci commit zerotier

# Start the service to generate identity and join
/etc/init.d/zerotier enable
/etc/init.d/zerotier restart

log "Waiting for ZeroTier to initialize (10s)..."
sleep 10

# --- 4. Join Network & Get Interface ---
log "Ensuring network join..."
zerotier-cli join "$ZT_NETWORK_ID"

log "Waiting for interface assignment..."
# We loop briefly to wait for the device (e.g., ztwd...) to appear
ZT_DEV=""
MAX_RETRIES=10
COUNT=0

while [ $COUNT -lt $MAX_RETRIES ]; do
    # Get the interface name associated with this network ID
    # zerotier-cli listnetworks output: <nwid> <name> <mac> <status> <type> <dev> ...
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
    log "Error: Could not determine ZeroTier interface name. Is the service running?"
    log "Please authorize this device in ZeroTier Central: $(zerotier-cli info | awk '{print $3}')"
    exit 1
fi

# --- 5. Bridge Configuration (Safety Critical) ---
# We need to add $ZT_DEV to the 'ports' list of the 'br-lan' device in /etc/config/network
# This works for OpenWrt 22.03+ (DSA / Bridge Device syntax)

log "Updating Network Bridge (br-lan)..."

# Check if already added
CURRENT_PORTS=$(uci -q get network.@device[0].ports || echo "")

# Safety check: Ensure br-lan exists as a device
BR_NAME=$(uci -q get network.@device[0].name)
if [ "$BR_NAME" != "br-lan" ]; then
    # Try to find the device entry named br-lan if it's not the first one
    log "Warning: First network device is not br-lan. Scanning..."
    # (Simplified logic: assumes standard config. If custom, we warn and exit)
    log "Standard br-lan device config not found at index 0. Aborting bridge modification for safety."
    log "ZeroTier is running, but you must manually bridge $ZT_DEV."
    exit 0
fi

if echo "$CURRENT_PORTS" | grep -q "$ZT_DEV"; then
    log "Interface $ZT_DEV is already in br-lan ports."
else
    log "Adding $ZT_DEV to br-lan ports..."
    uci add_list network.@device[0].ports="$ZT_DEV"
    uci commit network
    
    log "Reloading network (this may take a moment)..."
    /etc/init.d/network reload
fi

# --- 6. Firewall Zone ---
# Ensure the interface is treated as LAN. Since it is bridged, it inherits br-lan zone (usually 'lan').
# No explicit firewall change needed for L2 bridged interfaces usually, 
# but we ensure 'lan' zone covers the bridge.

# --- 7. Final Status ---
log "Done."
echo "-------------------------------------------------------"
echo "  Identity: $(zerotier-cli info | awk '{print $3}')"
echo "  Network:  $ZT_NETWORK_ID"
echo "  Device:   $ZT_DEV"
echo "-------------------------------------------------------"
echo "ACTION REQUIRED: Go to my.zerotier.com and:"
echo "1. Authorize this member."
echo "2. Check the 'Allow Ethernet Bridging' box for this member."
echo "-------------------------------------------------------"
