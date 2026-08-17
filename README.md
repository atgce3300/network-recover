Network-recover

Please read the details below:

if tailscale is connected

tailscale set --accept-dns=false

In crontab 
crontab -e 

#*/15 * * * * /root/net-recover.sh >> /root/net-recover.log 2>&1
*/15 * * * * /root/net-recover.sh 2>&1

In running lxc container run once

cat > /etc/systemd/network/eth0-dns.conf << 'EOF'
[Network]
DNS=8.8.8.8
DNS=8.8.4.4
EOF
systemctl restart systemd-networkd


openclaw-network-recover

In crontab 
crontab -e 

#* */3 * * * /root/openclaw-net-recover.sh >> /root/opencalw-net-recover.log 2>&1
* */3 * * * /root/openclaw-net-recover.sh 2>&1

Or
crontab -e

* */3 * * * root /usr/local/bin/openclaw-net-recover

For Alpine lxc container

Alpine doesn't use systemd or systemd-networkd — it uses OpenRC. Here's the Alpine way to persist DNS:
# 1. Stop udhcpc from overwriting resolv.conf
echo 'RESOLV_CONF="NO"' >> /etc/udhcpc/udhcpc.conf

# 2. Set static DNS
cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

# 3. Lock it down (optional but safe)
chattr +i /etc/resolv.conf
Alternative — configure via interfaces (cleaner, no chattr needed):
cat > /etc/network/interfaces << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

# Then reboot or:
/etc/init.d/networking restart
Actually the simplest one-liner for a run-once LXC:
bash
echo 'RESOLV_CONF="NO"' >> /etc/udhcpc/udhcpc.conf && echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" > /etc/resolv.conf && chattr +i /etc/resolv.conf
The key Alpine-specific piece is RESOLV_CONF="NO" in udhcpc.conf — that's what stops the DHCP client from blowing away your DNS every renew.
Oc
—
10:59 PM
tailscale:~# echo 'RESOLV_CONF="NO"' >> /etc/udhcpc/udhcpc.conf && echo -e "name server 8.8.8.8\nnameserver 1.1.1.1" > /etc/resolv.conf && chattr +i /etc/resolv. conf chattr: setting flags on /etc/resolv.conf: Operation not permitted tailscale:~#


chattr +i needs CAP_LINUX_IMMUTABLE which LXC containers don't have by default. But it's not strictly needed — RESOLV_CONF="NO" already stops udhcpc from overwriting it. That's the real fix on Alpine. So just:
echo 'RESOLV_CONF="NO"' >> /etc/udhcpc/udhcpc.conf
echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" > /etc/resolv.conf
Then verify it survives a DHCP renew:
# Force a renew to test
udhcpc -n -i eth0
cat /etc/resolv.conf
Should still show 8.8.8.8 and 1.1.1.1. If it does, you're good without chattr. But also check Tailscale's own DNS — it can override resolv.conf too:
tailscale dns status
If Tailscale MagicDNS is pushing its own resolvers, either:
Disable it: tailscale set --accept-dns=false
Or set your preferred nameservers in the Tailscale admin console under DNS settings
One of those two (udhcpc or Tailscale) is the culprit nuking your resolv.conf.



echo 'RESOLV_CONF="NO"' >> /etc/udhcpc/udhcpc.conf
echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" > /etc/resolv.conf

udhcpc -n -i eth0
cat /etc/resolv.conf

tailscale dns status

tailscale set --accept-dns=false

To resolve name resolution error

tailscale set --accept-dns=false

add
nameserver 8.8.8.8

at the end of  cat /etc/resolv.conf

