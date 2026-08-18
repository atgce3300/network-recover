# Network Recover

Automated network recovery scripts for Linux systems, especially useful for LXC containers and Tailscale users.

## Overview

Network connectivity issues can occur due to various reasons such as cable disconnection, DHCP lease expiration, or network interface flaps. This project provides scripts to automatically detect and recover network connectivity.

## Features

- **Automatic DHCP Recovery**: Automatically renews DHCP leases when network is down
- **Interface Monitoring**: Checks all network interfaces (except loopback and bonding)
- **WiFi Support**: Handles WiFi interfaces with wpa_supplicant
- **Tailscale DNS Fix**: Resolves DNS conflicts with Tailscale MagicDNS
- **LXC Container Support**: Auto-recovers network for running LXC containers
- **NAT Restoration**: Restores iptables NAT rules for container networking

## Scripts

### 1. net-recover.sh

General network recovery script for any Linux system.

**Usage:**
```bash
# Copy to system
sudo cp net-recover.sh /root/net-recover.sh
sudo chmod +x /root/net-recover.sh

# Test manually
sudo /root/net-recover.sh

# Set up cron job (every 15 minutes)
sudo crontab -e
*/15 * * * * /root/net-recover.sh
```

### 2. openclaw-net-recover.sh

Advanced network recovery script designed for Proxmox LXC containers with NAT.

**Usage:**
```bash
# Copy to system
sudo cp openclaw-net-recover.sh /usr/local/bin/openclaw-net-recover
sudo chmod +x /usr/local/bin/openclaw-net-recover

# Test manually
sudo /usr/local/bin/openclaw-net-recover

# Set up cron job (every 3 hours)
sudo crontab -e
*/3 * * * * /usr/local/bin/openclaw-net-recover
```

## Problem Solved

### The DHCP Lease Issue

When a network cable is unplugged and plugged back:

1. The DHCP lease is not automatically released
2. The interface may show no IP address in `ip a`
3. Internet remains disconnected even though the cable is connected

### The Solution

This script:
1. Checks if the network interface is UP
2. Always releases the DHCP lease before requesting a new IP
3. Kills any existing dhclient process
4. Flushes the old IP address
5. Requests a fresh IP via DHCP

## Supported Systems

| System | Support |
|--------|---------|
| Debian/Ubuntu | ✅ |
| Raspberry Pi | ✅ |
| Proxmox LXC | ✅ |
| Alpine Linux | ✅ (via DNS config) |
| Tailscale | ✅ (DNS fix) |

## Tailscale DNS Configuration

If using Tailscale, you may need to disable MagicDNS to prevent DNS conflicts:

```bash
# Disable Tailscale DNS
tailscale set --accept-dns=false
```

## Alpine Linux DNS Configuration

For Alpine Linux LXC containers:

```bash
# Stop udhcpc from overwriting resolv.conf
echo 'RESOLV_CONF="NO"' >> /etc/udhcpc/udhcpc.conf

# Set static DNS
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf

# Test
udhcpc -n -i eth0
cat /etc/resolv.conf
```

## Troubleshooting

### No network after cable plug

Run the recovery script manually:
```bash
sudo /root/net-recover.sh
```

### Check logs
```bash
# net-recover.sh logs
cat ~/net-recover.log

# openclaw-net-recover.sh logs
cat ~/openclaw-net-recover.log
```

### Check interface status
```bash
ip a
ip link show
```

### Check DHCP status
```bash
dhclient -v <interface>
```

## Configuration

### For openclaw-net-recover.sh

Edit the script to match your network configuration:

```bash
LOCAL_ROUTE="192.168.1.192/26"    # Your local route
LXC_GATEWAY="10.10.1.193"         # Your LXC gateway
ACTIVE_IFACE="wlxe0ad4732de36"    # Your active network interface
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License

## Author

Created to solve network connectivity issues in home lab environments.
