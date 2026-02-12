#!/usr/bin/env bash

debian_version=$(cat /etc/debian_version | cut -d'.' -f1)

# Only uninstall global ansible/passlib on Debian 11
# Debian 12 uses a virtualenv which will be cleaned up automatically
if [[ "$debian_version" == "11" ]]; then
  DEBIAN_FRONTEND=noninteractive sudo python3.9 -m pip uninstall -y --break-system-packages ansible passlib
fi

DEBIAN_FRONTEND=noninteractive sudo apt autoremove -y
DEBIAN_FRONTEND=noninteractive sudo apt clean
DEBIAN_FRONTEND=noninteractive sudo rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

exit 0
