#!/usr/bin/env bash

echo "Installing Brother printer drivers:"

echo "Ensuring 32-bit binary support..."
sudo dpkg --add-architecture i386
sudo apt update
sudo apt install libc6:i386 libncurses5:i386 libstdc++6:i386 -y

echo "Downloading drivers..."
wget https://download.brother.com/welcome/dlfp100949/pj822pdrv-1.2.0-1.i386.deb
wget https://download.brother.com/welcome/dlfp100952/pj823pdrv-1.2.0-1.i386.deb

echo "Installing drivers..."
sudo dpkg -i pj822pdrv-1.2.0-1.i386.deb pj823pdrv-1.2.0-1.i386.deb

echo "Cleaning up installation..."
rm pj822pdrv-1.2.0-1.i386.deb pj823pdrv-1.2.0-1.i386.deb
sudo lpadmin -x PJ-822
sudo lpadmin -x PJ-823

echo "Done."

