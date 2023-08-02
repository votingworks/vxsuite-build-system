#!/usr/bin/env bash

set -euo pipefail

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


if ! which ansible-playbook > /dev/null 2>&1
then
  echo "Installing Ansible..."
  cd $vxsuite_build_system_dir
  sudo ./scripts/tb-install-ansible.sh offline
  echo "Ansible installation is complete."
fi

echo "Run offline_build playbook. This will take several minutes."
sleep 5
cd $vxsuite_build_system_dir
ansible-playbook -i inventories/tb playbooks/trusted_build/offline_build.yaml --skip-tags online

echo "Build kiosk-browser. This may take several minutes."
sleep 5
cd $vxsuite_complete_system_dir
make offline-kiosk-browser

echo "Run build.sh in complete-system. This will take several minutes."
sleep 5
cd $vxsuite_complete_system_dir
./build.sh

echo "The offline build phase is complete."
echo "Depending on your needs, clone this VM and run setup-machine OR"
echo "run setup-machine in this VM, understanding it is destructive."
echo ""

exit 0
