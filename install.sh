#!/bin/sh
# ============================================================
# Project: rpi5-zerotier-bridge
# Baseline: rpi5-zerotier-bridge Baseline 1.1.0 (Safe + Robust)
# ============================================================
#
# Goals:
#  - Safe: never wipes /etc/config/zerotier or /etc/config/network
#  - Robust: works even if LuCI/UCI bridge config is odd by enforcing runtime bridge membership
#  - Installs: ZeroTier + common USB Ethernet driver set + firewall allow UDP/9993 inbound on WAN
#  - Auto: hotplug listener that attaches ANY zt* interface to br-lan whenever it appears
#
# Usage (no prompts):
#   NETID=154a350c86249d23 HOSTNAME=Router AUTO_REBOOT=1 sh ./install.sh
# Or (arg form):
#   sh ./install.sh 154a350c86249d23
#
# Optional env vars:
#   LAN_BRIDGE=br-lan            # default br-lan
#   INSTALL_USB_DRIVERS=1        # default 1 (set 0 to skip)
#   INSTALL_FIREWALL_RULE=1      # default 1 (set 0 to skip)
#   INSTALL_HOTPLUG=1            # default 1 (set 0 to skip)
#   AUTO_REBOOT=1                # reboot without prompt
#
# Notes:
#  - This script intentionally prefers runtime correctness (kernel bridge membership) over purely UCI.
#  - It does NOT assume @device[0] is br-lan. It finds the correct section (or creates it safely).
#  - It does NOT assume the ZeroTier interface name in a specific CLI column. It detects zt* via ip link.

set -eu

BASELINE_NAME="rpi5-zerotier-bridge"
BASELINE_VERSION="1.1.0"
LOG_FILE="/tmp/zt-install.log"

log() { printf "[%s] %s\n" "$BASELINE_NAME" "$1" | tee -a "$LOG_FILE" >&2; }
die() { log "ERROR: $1"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "This script must be run as root."

echo "▶ Deploying $BASELINE_NAME Baseline $BASELINE_VERSION"

OPKG_UPDATED=0
opkg_update_once() {
  if [ "$OPKG_UPDATED" -eq 0 ]; then
    log "Running opkg update..."
    opkg update >/dev/null 2>&1 || log "Warning: opkg update failed, continuing..."
    OPKG_UPDATED=1
  fi
}

opkg_install_if_missing() {
  PKG="$1"
  if opkg list-installed 2>/dev/null | awk '{print $1}' | grep -qx "$PKG"; then
    log "$PKG already installed."
    return 0
  fi
  opkg_update_once
  log "Installing $PKG..."
  opkg install "$PKG"
}

# -----------------------------
# Inputs
# -----------------------------
get_netid() {
  if [ -n "${1:-}" ]; then
    NET="$1"
  elif [ -n "${NETID:-}" ]; then
    NET="$NETID"
  else
    printf "\nEnter your ZeroTier Network ID (16 chars): " >/dev/tty
    read -r NET </dev/tty
  fi

  # strip whitespace
  NET="$(printf "%s" "$NET" | tr -d ' \t\r\n')"
  echo "$NET" | grep -Eq '^[0-9a-f]{16}$' || die "Network ID must be exactly 16 lowercase hex characters."
  echo "$NET"
}

get_hostname_optional() {
  if [ -n "${HOSTNAME:-}" ]; then
    echo "$HOSTNAME"
    return 0
  fi
  printf "Optional hostname (blank to skip): " >/dev/tty
  read -r HN </dev/tty || true
  echo "$HN"
}

set_hostname() {
  HN="$1"
  [ -n "$HN" ] || return 0
  log "Setting hostname: $HN"
  uci set system.@system[0].hostname="$HN"
  uci commit system
  /etc/init.d/system reload >/dev/null 2>&1 || true
}

# -----------------------------
# USB Ethernet driver set
# -----------------------------
install_usb_nic_drivers() {
  log "Installing common USB Ethernet drivers (broad set)..."

  # handy tools (optional)
  opkg_install_if_missing usbutils || true

  # core usb stack (safe if available)
  opkg_install_if_missing kmod-usb-core || true
  opkg_install_if_missing kmod-usb2 || true
  opkg_install_if_missing kmod-usb3 || true

  # PHY helpers
  opkg_install_if_missing kmod-mii || true

  # base usb networking + families
  opkg_install_if_missing kmod-usb-net
  opkg_install_if_missing kmod-usb-net-cdc-ether
  opkg_install_if_missing kmod-usb-net-rndis

  # ASIX including AX88179/178A (your AX88179A uses this)
  opkg_install_if_missing kmod-usb-net-asix
  opkg_install_if_missing kmod-usb-net-asix-ax88179

  # Realtek 8152/8153/8156 family
  opkg_install_if_missing kmod-usb-net-rtl8152

  # SMSC/Microchip LAN95xx
  opkg_install_if_missing kmod-usb-net-smsc95xx

  log "USB driver install complete."
  log "Tip: If a dongle is already plugged in, unplug/replug it to bind the driver."
}

# -----------------------------
# ZeroTier install + config (SAFE: no wiping)
# -----------------------------
ensure_zerotier_installed() {
  opkg_install_if_missing zerotier
}

configure_zerotier_uciconfig() {
  NET="$1"

  log "Configuring ZeroTier (safe UCI update, no file wipe)..."

  # Ensure global section exists and enabled
  uci -q set zerotier.global=zerotier
  uci -q set zerotier.global.enabled='1'

  # Remove default earth if present (harmless if missing)
  uci -q delete zerotier.earth || true

  # Use a deterministic section name to avoid duplicates
  uci -q delete zerotier.openwrt_network || true
  uci -q set zerotier.openwrt_network=network
  uci -q set zerotier.openwrt_network.id="$NET"

  uci commit zerotier

  /etc/init.d/zerotier enable >/dev/null 2>&1 || true
  /etc/init.d/zerotier restart >/dev/null 2>&1 || true
}

# -----------------------------
# Firewall: allow inbound UDP/9993 on WAN (SAFE: idempotent)
# -----------------------------
ensure_firewall_rule() {
  log "Ensuring firewall allows inbound UDP/9993 on WAN (ZeroTier)..."

  # If rule exists by name, do nothing
  if uci -q show firewall | grep -q "name='Allow-ZeroTier-Inbound'"; then
    log "Firewall rule Allow-ZeroTier-Inbound already exists."
    return 0
  fi

  uci add firewall rule >/dev/null
  uci set firewall.@rule[-1].name='Allow-ZeroTier-Inbound'
  uci set firewall.@rule[-1].src='wan'
  uci set firewall.@rule[-1].target='ACCEPT'
  uci set firewall.@rule[-1].proto='udp'
  uci set firewall.@rule[-1].dest_port='9993'
  uci commit firewall
  /etc/init.d/firewall restart >/dev/null 2>&1 || true

  log "Firewall rule created."
}

# -----------------------------
# Runtime auto-bridge: hotplug + helper
# -----------------------------
install_zt_hotplug_autobridge() {
  BR="${LAN_BRIDGE:-br-lan}"

  log "Installing zt* auto-bridge hotplug (runtime attach to $BR)..."

  cat > /usr/sbin/zt-auto-bridge.sh <<'SH'
#!/bin/sh
# zt-auto-bridge.sh
# Runtime enforcer: attach zt* interfaces to BRIDGE_NAME (default br-lan) using kernel bridge membership.

set -eu
BR="${BRIDGE_NAME:-br-lan}"
LOGTAG="zt-auto-bridge"

log() { logger -t "$LOGTAG" "$*"; }

br_exists() { [ -d "/sys/class/net/$BR" ]; }
is_in_bridge() { IF="$1"; [ -e "/sys/class/net/$BR/brif/$IF" ]; }

attach_to_bridge() {
  IF="$1"

  case "$IF" in
    zt*) : ;;
    *) return 0 ;;
  esac

  # Wait for bridge to exist (boot ordering)
  i=0
  while ! br_exists; do
    i=$((i+1))
    [ "$i" -le 30 ] || { log "Bridge $BR not present; giving up for $IF"; return 1; }
    sleep 1
  done

  if is_in_bridge "$IF"; then
    log "$IF already in $BR"
    return 0
  fi

  # Attach to kernel bridge
  if ip link set dev "$IF" master "$BR" 2>/dev/null; then
    ip link set dev "$IF" up 2>/dev/null || true
    log "Attached $IF to $BR"
    return 0
  fi

  log "FAILED attaching $IF to $BR"
  return 1
}

# One interface or all
if [ "${1:-}" != "" ]; then
  attach_to_bridge "$1" || true
  exit 0
fi

for IF in $(ls /sys/class/net 2>/dev/null | grep '^zt' || true); do
  attach_to_bridge "$IF" || true
done

exit 0
SH

  chmod +x /usr/sbin/zt-auto-bridge.sh

  cat > /etc/hotplug.d/net/99-zt-auto-bridge <<'SH'
#!/bin/sh
# Hotplug hook: when zt* appears, attach it to bridge at runtime.

[ -n "${DEVICE:-}" ] || exit 0

case "$DEVICE" in
  zt*)
    BRIDGE_NAME="${BRIDGE_NAME:-br-lan}" /usr/sbin/zt-auto-bridge.sh "$DEVICE" &
    ;;
esac

exit 0
SH

  chmod +x /etc/hotplug.d/net/99-zt-auto-bridge

  # Run once now (if zt* already exists)
  BRIDGE_NAME="$BR" /usr/sbin/zt-auto-bridge.sh || true

  log "Hotplug auto-bridge installed. View logs: logread -e zt-auto-bridge"
}

# -----------------------------
# Helpers: detect current zt* interface reliably
# -----------------------------
wait_for_zt_iface() {
  log "Waiting for ZeroTier interface (zt*) to appear..."
  /etc/init.d/zerotier restart >/dev/null 2>&1 || true

  i=0
  while [ "$i" -lt 60 ]; do
    ZT="$(ip -o link 2>/dev/null | awk -F': ' '{print $2}' | grep '^zt' | head -n1 || true)"
    if [ -n "${ZT:-}" ]; then
      log "Found ZeroTier interface: $ZT"
      echo "$ZT"
      return 0
    fi
    i=$((i+1))
    sleep 1
  done

  die "ZeroTier interface not found after 60s. Check: zerotier-cli info ; logread | grep -i zerotier"
}

# -----------------------------
# Main
# -----------------------------
NETID_VAL="$(get_netid "${1:-}")"
HN_VAL="$(get_hostname_optional)"
BR="${LAN_BRIDGE:-br-lan}"

log "Network ID: $NETID_VAL"
[ -n "${HN_VAL:-}" ] && set_hostname "$HN_VAL" || true

if [ "${INSTALL_USB_DRIVERS:-1}" = "1" ]; then
  install_usb_nic_drivers
else
  log "Skipping USB driver install (INSTALL_USB_DRIVERS=0)."
fi

ensure_zerotier_installed
configure_zerotier_uciconfig "$NETID_VAL"

if [ "${INSTALL_FIREWALL_RULE:-1}" = "1" ]; then
  ensure_firewall_rule
else
  log "Skipping firewall rule (INSTALL_FIREWALL_RULE=0)."
fi

if [ "${INSTALL_HOTPLUG:-1}" = "1" ]; then
  install_zt_hotplug_autobridge
else
  log "Skipping hotplug install (INSTALL_HOTPLUG=0)."
fi

# Attach current interface now (hotplug handles future events)
ZTIF="$(wait_for_zt_iface)"
BRIDGE_NAME="$BR" /usr/sbin/zt-auto-bridge.sh "$ZTIF" || true

log "ZeroTier status:"
zerotier-cli info || true
zerotier-cli listnetworks || true

log "Bridge members (runtime truth):"
ls -1 "/sys/class/net/$BR/brif" 2>/dev/null || true

echo "-------------------------------------------------------"
echo "  Network:  $NETID_VAL"
echo "  Bridge:   $BR"
echo "  ZT Dev:   $ZTIF"
echo "  Identity: $(zerotier-cli info 2>/dev/null | awk '{print $3}' || true)"
echo "-------------------------------------------------------"
echo "IMPORTANT: In my.zerotier.com, authorize this member and enable 'Ethernet Bridging' if you need L2 bridging."
echo "Logs: $LOG_FILE"
echo "Hotplug logs: logread -e zt-auto-bridge"

if [ "${AUTO_REBOOT:-0}" = "1" ]; then
  log "AUTO_REBOOT=1 set; rebooting now..."
  reboot
else
  printf "Reboot now? [Y/n]: " >/dev/tty
  read -r A </dev/tty || true
  if [ "${A:-Y}" != "n" ] && [ "${A:-Y}" != "N" ]; then
    reboot
  else
    log "Skipping reboot (recommended later)."
  fi
fi
