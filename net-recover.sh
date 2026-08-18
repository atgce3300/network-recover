#!/bin/bash
LOGFILE=~/net-recover.log


# ── 0. Bring ALL network interfaces up ──
# ── 1. Recover DHCP if IP is missing ──
# ── 2. Always try DHCP when interface is UP but has no IP ──


echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checking all interfaces..." | tee -a "$LOGFILE"


# Get all network interfaces (exclude loopback AND bonding)
for IFACE in $(ls /sys/class/net/ | grep -v '^lo$\|^bond'); do
    # Check if interface is UP
    STATE=$(cat /sys/class/net/$IFACE/operstate 2>/dev/null)
    
    # Check if interface has IP
    if ip addr show "$IFACE" 2>/dev/null | grep -q 'inet '; then
        IP=$(ip addr show "$IFACE" | grep 'inet ' | awk '{print $2}')
        
        # Test internet connectivity
        if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $IFACE: $IP is there ✅ (internet works)" | tee -a "$LOGFILE"
            continue
        else
            # Internet is down but IP exists - force DHCP renew
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $IFACE: $IP exists but no internet - forcing DHCP renew..." | tee -a "$LOGFILE"
        fi
    else
        # No IP - recover it
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $IFACE: No IP — recovering..." | tee -a "$LOGFILE"
    fi

    # Bring UP if down
    if [ "$STATE" = "down" ] || [ "$STATE" = "dormant" ]; then
        timeout 10 ip link set "$IFACE" up 2>/dev/null || ip link set "$IFACE" up 2>/dev/null &
        sleep 1
    fi

    # ── ALWAYS release DHCP lease before requesting new IP ──
    # This is critical when cable was unplugged and plugged back
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $IFACE: Releasing DHCP lease..." | tee -a "$LOGFILE"
    pkill -9 dhclient 2>/dev/null
    sleep 1
    dhclient -r "$IFACE" 2>/dev/null
    sleep 1
    ip addr flush dev "$IFACE" 2>/dev/null
    sleep 1

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
        # Ethernet - try DHCP
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $IFACE: requesting new IP via DHCP..." | tee -a "$LOGFILE"
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
