#!/bin/sh
# ============================================================
# Project: rpi5-zerotier-bridge
# Baseline: rpi5-zerotier-bridge Baseline 1.0.1 (Hotfix)
# ============================================================

set -euo pipefail

# --- Variables ---
BASELINE_NAME="rpi5-zerotier-bridge"
BASELINE_VERSION="1.0.1"
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
    
    # Force read from terminal to bypass curl pipe
    read -r input_id < /dev/tty
    
    # AGGRESSIVE SANITIZATION:
    # 1. 'tr -cd' deletes everything EXCEPT alphanumeric characters
    # 2. This removes spaces, newlines, carriage returns, and hidden symbols
    ZT_NETWORK_ID=$(echo "$input_id" | tr -cd 'a-zA-Z0-9')
    
    # Debug output to verify what was captured
    echo "   > Detected ID: $ZT_NETWORK_ID"
    echo "   > Length: ${#ZT_NETWORK_ID}"
fi

# Validation
if [ ${#ZT_NETWORK_ID} -ne 16 ]; then
    log "Error: Network ID must be exactly 16 characters. You entered ${#ZT_NETWORK_ID}."
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
# Reset join list to ensure idempotency
uci -q delete zerotier.@zerotier[0].join_list
uci add_list zerotier.@zerotier[0].join_list="$ZT_NETWORK_ID"
uci commit zerotier

# Enable and Restart Service
/etc/init.d/zerotier enable
/etc/init.d/zerotier restart

log "Waiting for ZeroTier to initialize (10s)..."
sleep 10

# --- 4. Join Network & Get Interface ---
log "Ensuring network join..."
zerotier-cli join "$ZT_NETWORK_ID"

log "Waiting for interface assignment..."
ZT_DEV=""
MAX_RETRIES=15
COUNT=0

while [ $COUNT -lt $MAX_RETRIES ]; do
    # Scan for the device name associated with our Network ID
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
    log "1. Check your Internet connection."
    log "2. Verify the Network ID is correct."
    log "3. Current Status: $(zerotier-cli listnetworks)"
    exit 1
fi

# --- 5. Bridge Configuration (Safety Critical) ---
log "Updating Network Bridge (br-lan)..."

# Safety check: Ensure br-lan exists
BR_NAME=$(uci -q get network.@device[0].name)
if [ "$BR_NAME" != "br-lan" ]; then
    log "Warning: First network device is not br-lan (found $BR_NAME). Aborting bridge modification."
    log "ZeroTier is running, but you must manually bridge $ZT_DEV."
    exit 0
fi

CURRENT_PORTS=$(uci -q get network.@device[0].ports || echo "")

if echo "$CURRENT_PORTS" | grep -q "$ZT_DEV"; then
    log "Interface $ZT_DEV is already in br-lan ports."
else
    log "Adding $ZT_DEV to br-lan ports..."
    uci add_list network.@device[0].ports="$ZT_DEV"
    uci commit network
    
    log "Reloading network (this may take a moment)..."
    /etc/init.d/network reload
fi

# --- 6. Final Status ---
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
