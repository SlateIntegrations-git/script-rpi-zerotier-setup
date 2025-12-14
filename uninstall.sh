#!/bin/sh
# ============================================================
# Project: rpi5-zerotier-bridge
# Script: Uninstall / Rollback
# ============================================================

set -euo pipefail

echo "▶ Starting Rollback for RPi5 ZeroTier Bridge..."

# 1. Identify Interface
ZT_NETWORK_ID=$(uci -q get zerotier.@zerotier[0].join_list | awk '{print $1}')
ZT_DEV=""

if [ -n "$ZT_NETWORK_ID" ]; then
    # Try to resolve device before we kill the service
    ZT_DEV=$(zerotier-cli listnetworks | grep "$ZT_NETWORK_ID" | awk '{print $8}' || echo "")
fi

# 2. Clean Network Config
if [ -n "$ZT_DEV" ] && [ "$ZT_DEV" != "-" ]; then
    echo "Removing $ZT_DEV from br-lan..."
    uci del_list network.@device[0].ports="$ZT_DEV" || true
else
    echo "Could not auto-detect interface name. Attempting to remove common patterns..."
    # Fallback cleanup logic would go here, but avoiding blind deletion is safer.
    echo "Please check /etc/config/network manually for lingering 'zt*' ports."
fi

uci commit network

# 3. Disable ZeroTier
echo "Stopping ZeroTier..."
/etc/init.d/zerotier stop
/etc/init.d/zerotier disable

# 4. Remove Package (Optional - commented out by default for safety)
# echo "Removing package..."
# opkg remove zerotier

# 5. Reload Network
echo "Reloading network..."
/etc/init.d/network reload

echo "Rollback complete. ZeroTier is disabled and unbridged."
