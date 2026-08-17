#!/bin/bash
# /usr/local/bin/openclaw-net-recover
# Auto-recover LXC internet after host WiFi flap
# Runs via cron every 2 minutes
# Deploy: echo '*/2 * * * * root /usr/local/bin/openclaw-net-recover' > /etc/cron.d/openclaw-network

LOGFILE=~/openclaw-net-recover.log 

LOCAL_ROUTE="192.168.1.192/26"
LXC_GATEWAY="10.10.1.193"

ACTIVE_IFACE="wlxe0ad4732de36" # Save the working interface 
 
# ── 0. Bring ALL network interfaces up ──
# ── 1. Recover DHCP if IP is missing ──
# ── 2. Force release DHCP lease if internet is down but IP exists ──


echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checking all interfaces..." | tee -a "$LOGFILE"


# Get all network interfaces (exclude loopback AND bonding)
for IFACE in $(ls /sys/class/net/ | grep -v '^lo$\|^bond'); do
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
            
            # Kill existing dhclient
            pkill -9 dhclient 2>/dev/null
            sleep 1
            
            # Release DHCP lease
            dhclient -r "$IFACE" 2>/dev/null
            sleep 1
            
            # Flush IP address
            ip addr flush dev "$IFACE" 2>/dev/null
            sleep 1
        fi
    else
        # THIS interface has no IP — recover it
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $IFACE: No IP — recovering..." | tee -a "$LOGFILE"
    fi

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


if [ -n "$ACTIVE_IFACE" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Using $ACTIVE_IFACE for recovery..." | tee -a "$LOGFILE" 
    # ── 3. Re-add local route (critical for reply traffic) ──
    # Route 
    if ! ip route show table local | grep -q "$LOCAL_ROUTE"; then
        echo "[$(date)] Local route missing — re-adding" >&2
        ip route add local "$LOCAL_ROUTE" dev "$ACTIVE_IFACE"
    fi

    # ── 4. Restore POSTROUTING NAT ──
    if ! iptables -t nat -C POSTROUTING -s 10.10.1.192/26 -o "$ACTIVE_IFACE" -j NETMAP --to "$LOCAL_ROUTE" 2>/dev/null; then
        echo "[$(date)] POSTROUTING rule missing — re-adding" >&2
        iptables -t nat -A POSTROUTING -s 10.10.1.192/26 -o "$ACTIVE_IFACE" -j NETMAP --to "$LOCAL_ROUTE"
    fi
else
    # No network at all!
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ NO NETWORK — Cannot recover!" | tee -a "$LOGFILE"
   exit 1
fi


# ── 5. Restore PREROUTING NAT ──
if ! iptables -t nat -C PREROUTING -d "$LOCAL_ROUTE" -j NETMAP --to 10.10.1.192/26 2>/dev/null; then
	echo "[$(date)] PREROUTING rule missing — re-adding" >&2
	iptables -t nat -A PREROUTING -d "$LOCAL_ROUTE" -j NETMAP --to 10.10.1.192/26
fi

# ── 6. Ensure ip_forward is on ──
echo 1 > /proc/sys/net/ipv4/ip_forward

# ── 7 & 8. Recover all running LXC containers ──
for CTID in $(pct list | awk 'NR>1 && $2=="running" {print $1}'); do
   # Only bounce if the container can't reach the gateway
	if ! pct exec "$CTID" -- ping -c1 -W2 "$LXC_GATEWAY" >/dev/null 2>&1; then
		echo "[$(date)] CT $CTID unreachable — bouncing network" >&2
		pct exec "$CTID" -- bash -c '
			ip link set eth0 down; sleep 1; ip link set eth0 up
			ip route replace default via '"$LXC_GATEWAY"'
			ip neigh flush all
		'
	fi



# DNS safety net — test actual resolution, not just routing
if ! pct exec "$CTID" -- bash -c 'getent hosts google.com >/dev/null 2>&1'; then
	echo "[$(date)] CT $CTID DNS broken — fixing" >&2
	pct exec "$CTID" -- bash -c '
		echo "nameserver 8.8.8.8" > /etc/resolv.conf
		echo "nameserver 8.8.4.4" >> /etc/resolv.conf
		#systemctl restart systemd-resolved 2>/dev/null
		#tailscale set --accept-dns=false 2>/dev/null
	'
fi

done
