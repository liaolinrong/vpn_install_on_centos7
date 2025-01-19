#!/bin/bash


if [ $# != 1 ]; then
    echo "USAGE: $0 IP" >/dev/stderr
    echo " e.g.: $0 192.168.48.126(内网地址)" >/dev/stderr
    exit 1;
fi

systemctl stop firewalld
systemctl disable firewalld

yum install iptables-services -y
systemctl start iptables
systemctl enable iptables

yum install epel-release -y
yum install openswan -y
yum install xl2tpd -y

mv  /etc/ipsec.conf  /etc/ipsec.conf.bak
cat >> /etc/ipsec.conf <<-EOF
config setup
        protostack=netkey
        logfile=/var/log/pluto.log
        dumpdir=/var/run/pluto/
        virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12,%v4:25.0.0.0/8,%v4:100.64.0.0/10,%v6:fd00::/8,%v6:fe80::/10
include /etc/ipsec.d/*.conf
EOF

mv /etc/ipsec.d/vpn.conf /etc/ipsec.d/vpn.conf.bak

cat >> /etc/ipsec.d/vpn.conf <<-EOF
conn   %default
       Forceencaps=yes

conn L2TP-PSK-NAT
      rightsubnet=vhost:%priv
      also=L2TP-PSK-noNAT

conn L2TP-PSK-noNAT  
      authby=secret
      pfs=no
      auto=add 
      keyingtries=3
      rekey=no
      ikelifetime=8h
      keylife=1h
      type=transport
      left=$1
      leftprotoport=17/1701  
      right=%any           
      rightprotoport=17/%any
      #enable DPD
      dpddelay=40
      dpdtimeout=130
      dpdaction=clear
EOF

mv /etc/ipsec.d/user.secrets /etc/ipsec.d/user.secrets.bak
cat >> /etc/ipsec.d/user.secrets <<-EOF
$1 %any: PSK "liaolinrong"
EOF

mv /etc/sysctl.conf /etc/sysctl.conf.bak
cat >> /etc/sysctl.conf <<-EOF
net.ipv6.conf.all.accept_ra = 2
net.ipv6.conf.eth0.accept_ra = 2
net.ipv4.ip_forward = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.venet0.rp_filter = 0
net.ipv4.conf.venet0.arp_filter = 0
net.ipv4.conf.eth0.rp_filter = 0
net.ipv4.conf.lo.rp_filter = 0
EOF


sysctl -p

#echo 0 > /proc/sys/net/ipv4/conf/eth0/rp_filter
#echo 0 > /proc/sys/net/ipv4/conf/lo/rp_filter

systemctl ipsec start
ipsec verify


#配置xl2tp
mv /etc/xl2tpd/xl2tpd.conf /etc/xl2tpd/xl2tpd.conf.bak
cat >> /etc/xl2tpd/xl2tpd.conf <<-EOF
[global]

[lns default]
ip range = 192.168.1.128-192.168.1.254
local ip = 192.168.1.99
require chap = yes
refuse pap = yes
require authentication = yes
name = LinuxVPNserver
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

mv /etc/ppp/options.xl2tpd /etc/ppp/options.xl2tpd.bak
cat >> /etc/ppp/options.xl2tpd <<-EOF
ipcp-accept-local
ipcp-accept-remote
ms-dns 114.114.114.114
ms-dns  8.8.8.8
noccp
auth
#crtscts
idle 1800
mtu 1410
mru 1410
nodefaultroute
debug
#lock
proxyarp
connect-delay 5000
EOF

echo "liao  *       linrong       *" >> /etc/ppp/chap-secrets

systemctl start xl2tpd

iptables -t nat -A POSTROUTING -m policy --dir out --pol none -j MASQUERADE
iptables -I FORWARD -i ppp+ -p all -m state --state NEW,ESTABLISHED,RELATED    -j ACCEPT
iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -t nat -I POSTROUTING -s 192.168.1.0/24 -o eth0 -j MASQUERADE

iptables -I INPUT -p udp --dport 1701 -j ACCEPT
iptables -I INPUT -p udp --dport 500 -j ACCEPT
iptables -I INPUT -p udp --dport 4500 -j ACCEPT

service iptables save

systemctl restart ipsec
systemctl restart xl2tpd

systemctl enable xl2tpd
systemctl enable iptables
systemctl enable ipsec

