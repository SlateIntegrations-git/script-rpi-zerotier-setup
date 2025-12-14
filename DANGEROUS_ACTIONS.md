# Dangerous Actions Checklist

The following actions are considered risky in this deployment context. The `install.sh` script is designed to avoid these specific pitfalls.

## Network Integrity
- **Removing `br-lan`**: Never delete the main bridge; only append ports to it.
- **Overwriting WAN**: The script must never touch the `wan` or `wwan` interfaces used for initial setup.
- **Static IP Conflicts**: Bridging a ZeroTier network can introduce IP conflicts if the remote network and local network share subnets.

## Access
- **Firewall Flushing**: Do not flush global firewall rules; rely on zone inheritance.
- **SSH Lockout**: Do not restart the network without `&&` logic or verify config syntax first.

## System
- **Flash Space**: Check for available space before installing packages to avoid half-installed states.
