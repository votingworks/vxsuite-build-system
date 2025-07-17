#!/bin/bash
VXDEV_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_SCRIPT_DIR="$VXDEV_SCRIPT_DIR/../"
BASE_DIR="$(pwd)/$(git rev-parse --show-cdup)"

echo "This script will set up a VxDev machine for VxPollbook development."
echo "This assumes you are able to use a wifi card that supports mesh networking."
echo "Ctrl+C to cancel."
sleep 5
echo "Proceeding..."

pushd $BASE_DIR
ansible-playbook -i inventories/vxpollbook-latest playbooks/trusted_build/packages.yaml
ansible-playbook -i inventories/vxpollbook-latest playbooks/trusted_build/pollbook_label_printer.yaml
popd 

sudo usermod -aG dialout vx-services
sudo usermod -aG plugdev vx-services
# # Strongswan config and apparmor profile
sudo cp "$BASE_SCRIPT_DIR/swanmesh.conf" /etc/swanctl/conf.d/.
sudo cp "$BASE_SCRIPT_DIR/apparmor.d/usr.sbin.swanctl" /etc/apparmor.d/.

# Move mesh network configuration files
sudo cp "$BASE_SCRIPT_DIR/setup_basic_mesh.sh" /vx/scripts/.
sudo cp "$BASE_SCRIPT_DIR/join-mesh-network.service" /etc/systemd/system/.
sudo cp "$BASE_SCRIPT_DIR/avahi-autoipd.service" /etc/systemd/system/.
sudo cp "$BASE_SCRIPT_DIR/99-mesh-network.rules" /etc/udev/rules.d/.

# Barcode scanner udev rules
sudo cp "$BASE_SCRIPT_DIR/70-ts100-plugdev-usb.rules" /etc/udev/rules.d/.
sudo cp "$BASE_SCRIPT_DIR/99-ts100-dialout-tty.rules" /etc/udev/rules.d/.

cd "$VXDEV_SCRIPT_DIR"

sudo cp "$VXDEV_SCRIPT_DIR/run-vxpollbook.sh" /vx/scripts/.
sudo cp "$VXDEV_SCRIPT_DIR/update-vxpollbook.sh" /vx/scripts/.
sudo cp "$VXDEV_SCRIPT_DIR/run-vxpollbook.desktop" /usr/share/applications/.
sudo cp "$VXDEV_SCRIPT_DIR/update-vxpollbook.desktop" /usr/share/applications/.

gsettings set org.gnome.shell favorite-apps "['run-vxpollbook.desktop', 'update-vxpollbook.desktop', 'org.gnome.Screenshot.desktop', 'firefox-esr.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop']"

#sudo systemctl disable NetworkManager
sudo systemctl disable firewalld
#sudo systemctl stop NetworkManager
sudo systemctl stop firewalld

read -p "Enter Machine ID (leave empty to keep unchanged): " MACHINE_ID
if [ -n "$MACHINE_ID" ]; then
    sudo mkdir -p /vx/config
    echo "$MACHINE_ID" | sudo tee /vx/config/machine-id > /dev/null
fi

sudo udevadm control --reload-rules
sudo systemctl daemon-reload
sudo systemctl enable join-mesh-network
sudo systemctl enable avahi-daemon
sudo systemctl enable avahi-autoipd

sudo systemctl start avahi-autoipd
sudo systemctl start join-mesh-network
