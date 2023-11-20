#!/usr/bin/env bash

#DEBIAN_FRONTEND=noninteractive sudo python3.9 -m pip uninstall -y ansible passlib
DEBIAN_FRONTEND=noninteractive sudo apt autoremove -y
DEBIAN_FRONTEND=noninteractive sudo apt clean
DEBIAN_FRONTEND=noninteractive sudo rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

exit 0
