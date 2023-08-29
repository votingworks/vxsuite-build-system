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

if ! which ansible-playbook > /dev/null 2>&1
then
  echo "Installing Ansible..."
  cd $vxsuite_build_system_dir
  sudo ./scripts/tb-install-ansible.sh online
  echo "Ansible installation is complete."
fi

cd $vxsuite_build_system_dir

if [[ "$debian_major_version" == "12" ]]; then
  source .virtualenv/ansible/bin/activate
fi

echo "Run prepare_for_build playbook. This will take several minutes."
sleep 5
ansible-playbook -i inventories/tb playbooks/trusted_build/prepare_for_build.yaml

if [[ ! -d $vxsuite_complete_system_dir ]]; then
  echo "ERROR: vxsuite-complete-system could not be found."
  exit 1
fi

echo "Run prepare_build.sh in complete-system. This will take several minutes."
sleep 5
cd $vxsuite_complete_system_dir
./prepare_build.sh

echo "Download necessary tools for TPM."
sleep 5
cd $vxsuite_build_system_dir
ansible-playbook -i inventories/tb playbooks/trusted_build/tpm.yaml --skip-tags offline

echo "The online phase is complete. Please insert a USB drive and run: "
echo "ansible-playbook -i inventories/tb playbooks/trusted_build/export_to_usb.yaml"

exit 0
