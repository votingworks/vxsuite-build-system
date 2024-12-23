#!/usr/bin/env bash

set -euo pipefail

debian_major_version=$(cat /etc/debian_version | cut -d'.' -f1)
local_user=`logname`
local_user_home_dir=$( getent passwd "${local_user}" | cut -d: -f6 )
vxsuite_build_system_dir="${local_user_home_dir}/code/vxsuite-build-system"
vxsuite_complete_system_dir="${local_user_home_dir}/code/vxsuite-complete-system"

if [[ ! -d $vxsuite_build_system_dir ]]; then
  echo "ERROR: vxsuite-build-system could not be found."
  exit 1
fi

if [[ ! -d $vxsuite_complete_system_dir ]]; then
  echo "ERROR: vxsuite-complete-system could not be found."
  exit 1
fi

ansible_inventory=$1

if [[ ! -d ${vxsuite_build_system_dir}/inventories/${ansible_inventory} ]]; then
  echo "ERROR: The $ansible_inventory inventory could not be found."
  echo "You can find a list of inventories in: ${vxsuite_build_system_dir}/inventories"
  exit 1
fi

if [[ ! -f .virtualenv/ansible/bin/activate ]]; then
  echo "Installing Ansible..."
  cd $vxsuite_build_system_dir
  sudo ./scripts/tb-install-ansible.sh offline
  echo "Ansible installation is complete."
fi

echo "Run offline_build playbook. This will take several minutes."
sleep 5
cd $vxsuite_build_system_dir

if [[ "$debian_major_version" == "12" ]]; then
  source .virtualenv/ansible/bin/activate
fi

# Ensure sudo credentials haven't expired
sudo -v

ansible-playbook -i inventories/${ansible_inventory} playbooks/trusted_build/offline_build.yaml --skip-tags online

echo "Build kiosk-browser. This may take several minutes."
sleep 5
cd $vxsuite_complete_system_dir
make offline-kiosk-browser

echo "Run build.sh in complete-system. This will take several minutes."
sleep 5
cd $vxsuite_complete_system_dir
./build.sh

# Node20 upgrade has modified the permissions on some cached build dirs
# Reset them so they can later be deleted during final image creation
sudo chown -R ${local_user}:${local_user} ${local_user_home_dir}/.*

echo "The offline build phase is complete."
echo "Depending on your needs, clone this VM and run setup-machine OR"
echo "run setup-machine in this VM, understanding it is destructive."
echo ""

exit 0
