#!/usr/bin/env bash


if [[ -z $1 ]]; then
  vm_to_clone="online"
else
  vm_to_clone=$1
fi

echo "Attempting to clone ${vm_to_clone} to the offline VM..."

set -euo pipefail

debian_major_version=$(cat /etc/debian_version | cut -d'.' -f1)
local_user=`logname`
local_user_home_dir=$( getent passwd "${local_user}" | cut -d: -f6 )
vxsuite_build_system_dir="${local_user_home_dir}/code/vxsuite-build-system"

if [[ ! -d $vxsuite_build_system_dir ]]; then
  echo "ERROR: vxsuite-build-system could not be found."
  exit 1
fi

if [[ ! -f .virtualenv/ansible/bin/activate ]]; then
  echo "Installing Ansible..."
  cd $vxsuite_build_system_dir
  sudo ./scripts/tb-install-ansible.sh
  echo "Ansible installation is complete."
fi

cd $vxsuite_build_system_dir

if [[ "$debian_major_version" == "12" ]]; then
  source .virtualenv/ansible/bin/activate
fi

# Ensure sudo credentials haven't expired
sudo -v

sleep 5
ansible-playbook playbooks/virtmanager/create-offline-clone.yaml -e "vm_to_clone=${vm_to_clone}"

exit 0
