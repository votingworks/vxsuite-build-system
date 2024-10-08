#!/usr/bin/env bash

echo "Enabling i386 support..."
dpkg --add-architecture i386

echo "Updating apt repo sources..."
apt update

echo "Installing printer dependencies..."
apt install -y libc6:i386 libncurses5:i386 libstdc++6:i386

cd /tmp

echo "Downloading printer drivers..."
wget https://download.brother.com/welcome/dlfp100949/pj822pdrv-1.2.0-1.i386.deb
wget https://download.brother.com/welcome/dlfp100573/ql1100pdrv-2.1.4-0.i386.deb

echo "Installing PJ-822 driver..."
dpkg -i /tmp/pj822pdrv-1.2.0-1.i386.deb

sleep 10

echo "Installing QL-1100 driver..."
dpkg -i /tmp/ql1100pdrv-2.1.4-0.i386.deb

sleep 10

echo "Printer configuration is complete."

exit 0;
