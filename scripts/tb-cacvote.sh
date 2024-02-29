#!/usr/bin/env bash

set -euo pipefail

debian_major_version=$(cat /etc/debian_version | cut -d'.' -f1)
local_user=`logname`
local_user_home_dir=$( getent passwd "${local_user}" | cut -d: -f6 )
vxsuite_build_system_dir="${local_user_home_dir}/code/vxsuite-build-system"
kiosk_browser_dir="${local_user_home_dir}/code/kiosk-browser"

ansible_inventory=$1

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

echo "Run cacvote_build playbook. This will take several minutes."
sleep 5
ansible-playbook -i inventories/${ansible_inventory} playbooks/trusted_build/cacvote_build.yaml

if [[ ! -d $kiosk_browser_dir ]]; then
  echo "ERROR: kiosk-browser directory could not be found."
  exit 1
fi

echo "Build kiosk-browser"
sleep 5
cd $kiosk_browser_dir
make install
make build
sudo dpkg -i dist/kiosk-browser_1.0.0_*.deb

exit 0
