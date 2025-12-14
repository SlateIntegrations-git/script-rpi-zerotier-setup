# Changelog

All notable changes to this project are documented here.

This project follows a **Baseline Versioning Model**:
- **MAJOR** versions may introduce breaking or architectural changes
- **MINOR** versions include fixes, safety improvements, or enhancements
- Baselines are immutable once released

---

## [Baseline 1.0] – 2025-12-13

### Summary
Initial release of the RPi5 ZeroTier Bridge. Enables Layer 2 bridging of a ZeroTier network into the local LAN on OpenWrt 24.x devices.

### Added
- Automated installation of `zerotier` package
- Interactive prompt for ZeroTier Network ID
- logic to detect the dynamically assigned ZeroTier interface name
- UCI scripting to add the ZeroTier interface to `br-lan` ports
- Persistence checks for power cycles
- `uninstall.sh` for full rollback

### Safety Impact
- **Medium** – Modifies the `br-lan` bridge configuration. This allows traffic to flow from the VPN directly into the LAN.

### Upgrade Notes
- Safe to install on fresh OpenWrt 24.x setups.

### Rollback
- Run `sh uninstall.sh` to leave the network and remove the interface from the bridge.
