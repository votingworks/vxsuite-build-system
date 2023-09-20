#!/usr/bin/env bash

set -euo pipefail

default_phase="online"
phase=${1:-$default_phase}

if [ "$phase" != "online" ] && [ "$phase" != "offline" ]; then
  echo "Error: Invalid phase. Please specify either 'online' or 'offline'."
  exit 1
fi

debian_major_version=$(cat /etc/debian_version | cut -d'.' -f1)
system_architecture=$(uname -m)
local_user=`logname`

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

function apt_install ()
{
  local phase=$1
  if [[ "$debian_major_version" == "12" ]]; then
    local python_packages="python3=3.11.2-1+b1 python3-pip=23.0.1+dfsg-1 python3-virtualenv=20.17.1+ds-1"
  else
    local python_packages="python3.9=3.9.2-1 python3-pip=20.3.4-4+deb11u1"
  fi

  if [ "$phase" == "online" ]; then
    apt-get install --reinstall --download-only -y ${python_packages}
    apt-get install -y ${python_packages}
  fi

  if [ "$phase" == "offline" ]; then
    apt-get install -y ${python_packages}
  fi
}

function pip_install ()
{
  local phase=$1
  local pip_requirements="${DIR}/pip_deb${debian_major_version}_${system_architecture}_requirements.txt"

  if [[ "$debian_major_version" == "12" ]]; then
    cd ${DIR}/..
    mkdir -p .virtualenv
    cd .virtualenv && virtualenv ansible
    cd ..
    source .virtualenv/ansible/bin/activate
  fi

  if [ "$phase" == "online" ]; then
    pip3 download -d /var/tmp/downloads --require-hashes -r $pip_requirements
    pip3 install --no-index --find-links /var/tmp/downloads --require-hashes -r $pip_requirements
  fi

  if [ "$phase" == "offline" ]; then
    pip3 install --no-index --find-links /var/tmp/downloads --require-hashes -r $pip_requirements
  fi

  # We need to make sure the local user's virtualenv isn't owned by root
  # so that complete-system setup-machine can delete it
  if [[ "$debian_major_version" == "12" ]]; then
    cd ${DIR}/..
    chown -R ${local_user}:${local_user} .virtualenv   
  fi
}

apt_install $phase
pip_install $phase

echo "Done"
exit 0
