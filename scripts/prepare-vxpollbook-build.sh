#!/usr/bin/env bash

set -euo pipefail

debian_major_version=$(cat /etc/debian_version | cut -d'.' -f1)
local_user=`logname`
local_user_home_dir=$( getent passwd "${local_user}" | cut -d: -f6 )
vxsuite_build_system_dir="${local_user_home_dir}/code/vxsuite-build-system"
kiosk_browser_dir="${local_user_home_dir}/code/kiosk-browser"
complete_system_dir="${local_user_home_dir}/code/vxsuite-complete-system"
pollbook_dir="${local_user_home_dir}/code/vxsuite/apps/pollbook"

ansible_inventory='vxpollbook-latest'

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

# Ensure sudo credentials haven't expired
sudo -v

echo "Run vxpollbook playbook. This will take several minutes."
sleep 5
ansible-playbook -i inventories/${ansible_inventory} playbooks/trusted_build/pollbook_build.yaml

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

echo "Build VxPollbook"
sleep 5
# Make sure cargo is available in case it hasn't been sourced yet
export PATH="${local_user_home_dir}/.cargo/bin:${PATH}"
cd $pollbook_dir
pnpm install
export BUILD_ROOT="${local_user_home_dir}/build"
set +e
  (
    set -euo pipefail

    cd "${pollbook_dir}/frontend"

    BUILD_ROOT="${BUILD_ROOT}/vxpollbook" ./script/prod-build

    cp -rp \
      "${vxsuite_build_system_dir}/scripts/pollbook-files/run-vxpollbook.sh" \
      "${complete_system_dir}/run-scripts/run-kiosk-browser.sh" \
      "${complete_system_dir}/run-scripts/run-kiosk-browser-forever-and-log.sh" \
      "${complete_system_dir}/config" \
      "${complete_system_dir}/app-scripts" \
      "${complete_system_dir}/setup-scripts/setup-logging.sh" \
      "${BUILD_ROOT}"
  )

exit 0
