#!/usr/bin/env bash

set -euo pipefail

default_inventory="vxdev-stable"
ansible_inventory=${1:-$default_inventory}

debian_major_version=$(cat /etc/debian_version | cut -d'.' -f1)
local_user=`logname`
local_user_home_dir=$( getent passwd "${local_user}" | cut -d: -f6 )
vxsuite_build_system_dir="${local_user_home_dir}/code/vxsuite-build-system"
vxsuite_complete_system_dir="${local_user_home_dir}/code/vxsuite-complete-system"

if [[ ! -d ${vxsuite_build_system_dir}/inventories/${ansible_inventory} ]]; then
  echo "ERROR: The $ansible_inventory inventory could not be found."
  echo "You can find a list of inventories in: ${vxsuite_build_system_dir}/inventories"
  exit 1
fi

if [[ ! -d $vxsuite_build_system_dir ]]; then
  echo "ERROR: vxsuite-build-system could not be found."
  exit 1
fi

if [[ ! -f .virtualenv/ansible/bin/activate ]]; then
  echo "Installing Ansible..."
  cd $vxsuite_build_system_dir
  sudo ./scripts/tb-install-ansible.sh online
  echo "Ansible installation is complete."
fi

cd $vxsuite_build_system_dir

if [[ "$debian_major_version" == "12" ]]; then
  source .virtualenv/ansible/bin/activate
fi

echo "Run setup_vxdev playbook. This will take several minutes."
sleep 5
ansible-playbook -i inventories/${ansible_inventory} playbooks/trusted_build/setup_vxdev.yaml

if [[ ! -d $vxsuite_complete_system_dir ]]; then
  echo "ERROR: vxsuite-complete-system could not be found."
  exit 1
fi

echo "Run vxdev/setup-vxdev-base-machine.sh in complete-system. This will take several minutes."
sleep 5
cd $vxsuite_complete_system_dir
sudo -v
./vxdev/setup-vxdev-base-machine.sh

# If in an interactive session, help set up the dock
if [[ "${DESKTOP_SESSION}" == "gnome" ]]; then
  echo -e "\n\n"
  echo "Please install the Dash to Dock extension from Firefox. (Opening in 5 seconds.)"
  echo "Once you've done that, close Firefox to proceed."
  sleep 5
  firefox https://extensions.gnome.org/extension/307/dash-to-dock
  gnome-extensions enable dash-to-dock@micxgx.gmail.com
  dconf write /org/gnome/shell/extensions/dash-to-dock/dock-position "'LEFT'"
  dconf write /org/gnome/shell/extensions/dash-to-dock/intellihide true
fi

echo "Enabling live USB support..."
sudo /usr/sbin/grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable

echo "VxDev set up is complete." 

exit 0
