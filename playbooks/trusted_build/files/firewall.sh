#!/bin/bash

# Notes:
# - initial script form for ease of use when testing on configured systems
# - this should move to the firewalld playbook for the final version
# - 5353 port is for multicast peer discovery
# - 500,4500 are ipsec/esp ports
# - these rules are additive to the current firewalld config
# 
ll_net="169.254.0.0/16"
base_command="firewall-cmd --permanent --direct --add-rule ipv4 raw"

# ---- inbound (filter on source) ----
$base_command PREROUTING 0 -i lo -j ACCEPT
$base_command PREROUTING 0 -s $ll_net -p udp --dport 5353 -j ACCEPT
$base_command PREROUTING 0 -s $ll_net -p udp -m multiport --dports 500,4500 -j ACCEPT
$base_command PREROUTING 0 -s $ll_net -p esp -j ACCEPT
$base_command PREROUTING 0 -s $ll_net -m policy --dir in --pol ipsec --mode transport --proto esp -j ACCEPT
$base_command PREROUTING 1 -s $ll_net -j DROP

#--- outbound (filter on destination) ----
$base_command OUTPUT 0 -o lo -j ACCEPT
$base_command OUTPUT 0 -d $ll_net -p udp --dport 5353 -j ACCEPT
$base_command OUTPUT 0 -d $ll_net -p udp -m multiport --dports 500,4500 -j ACCEPT
$base_command OUTPUT 0 -d $ll_net -p esp -j ACCEPT
$base_command OUTPUT 0 -d $ll_net -m policy --dir out --pol ipsec --mode transport --proto esp -j ACCEPT
$base_command OUTPUT 1 -d $ll_net -j DROP

firewall-cmd --reload
systemctl restart strongswan

exit 0
