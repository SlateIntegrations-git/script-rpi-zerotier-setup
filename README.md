# RPi5 ZeroTier Bridge

### RPi5 ZeroTier Bridge Baseline 1.0

## What This Does (Plain English)
This project provides a one-command setup that configures an OpenWrt router (specifically Raspberry Pi 5) to:
- Install the ZeroTier VPN software
- Join a private ZeroTier network you provide
- **Bridge** that VPN connection directly into your physical LAN
- Ensure the connection reconnects automatically after a power cut

This is designed for **non-technical users** setting up "site-to-site" or "remote access" bridges.
You do **not** need prior OpenWrt or Linux experience.

> **Important:** You must enable "Allow Ethernet Bridging" for this member in your ZeroTier Central controller settings for this to work correctly.

---

## Supported Devices & Versions
**OpenWrt Versions**
- Tested: OpenWrt 24.10.x (Snapshot/Stable)
- Expected to work: OpenWrt 23.05.x
- Not supported: Versions older than 22.03

**Hardware**
- Tested on: Raspberry Pi 5
- Minimum recommended: Any ARM64 device with 512MB RAM

---

## One-Line Install (Recommended)
Run this on your OpenWrt router:

```sh
curl -fsSL https://raw.githubusercontent.com/SlateIntegrations-git/script-rpi-zerotier-setup/main/install.sh | sh
