#!/bin/bash
LOGFILE=~/net-recover.log


# ── 0. Bring ALL network interfaces up ──
# ── 1. Recover DHCP if IP is missing ──


echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checking all interfaces..." | tee -a "$LOGFILE"


# Get all network interfaces (exclude loopback AND bonding)
for IFACE in $(ls /sys/class/net/ | grep -v '^lo$\|^bond'); do
# Skip if already has IP
if ip addr show "$IFACE" 2>/dev/null | grep -q 'inet '; then
IP=$(ip addr show "$IFACE" | grep 'inet ' | awk '{print $2}')
echo "[$(date '+%Y-%m-%d %H:%M:%S')] $IFACE: $IP is there ✅ (skipped)" | tee -a "$LOGFILE"
continue
fi
# THIS interface has no IP — recover it
echo "[$(date '+%Y-%m-%d %H:%M:%S')] $IFACE: No IP — recovering..." | tee -a "$LOGFILE"


# ONLY bring UP if it's down - with timeout
STATE=$(cat /sys/class/net/$IFACE/operstate 2>/dev/null)
if [ "$STATE" = "down" ] || [ "$STATE" = "dormant" ]; then
timeout 10 ip link set "$IFACE" up 2>/dev/null || ip link set "$IFACE" up 2>/dev/null &
sleep 1
fi


# WiFi = restart wpa_supplicant
if [[ "$IFACE" == wlx* ]]; then
echo "[$(date '+%Y-%m-%d %H:%M:%S')] $IFACE: WiFi recovery and try DHCP" | tee -a "$LOGFILE"
pkill -f "wpa_supplicant.*$IFACE" 2>/dev/null
sleep 1
wpa_supplicant -B -i "$IFACE" -c /etc/wpa_supplicant/wpa_supplicant.conf -Dnl80211 2>&1 | tee -a "$LOGFILE"
sleep 5
echo "[$(date '+%Y-%m-%d %H:%M:%S')] $IFACE: getting IP..." | tee -a "$LOGFILE"
timeout 15 dhclient -v "$IFACE" 2>&1 | tee -a "$LOGFILE"
sleep 3 
else
# Ethernet - just try DHCP (don't wait long)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] $IFACE: trying DHCP..." | tee -a "$LOGFILE"
timeout 15 dhclient "$IFACE" 2>&1 | tee -a "$LOGFILE"
sleep 2
fi


# Check result
if ip addr show "$IFACE" 2>/dev/null | grep -q 'inet '; then
IP=$(ip addr show "$IFACE" | grep 'inet ' | awk '{print $2}')
echo "[$(date '+%Y-%m-%d %H:%M:%S')] $IFACE: $IP ✅ recovered" | tee -a "$LOGFILE"
else
echo "[$(date '+%Y-%m-%d %H:%M:%S')] $IFACE: no cable or failed 😞" | tee -a "$LOGFILE"
fi
done
