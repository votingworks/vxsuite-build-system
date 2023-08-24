#!/usr/bin/env bash

set -euo pipefail

phase=$1

if [ "$phase" != "online" ] && [ "$phase" != "offline" ] && [ "$phase" != "" ]; then
  echo "Error: Invalid phase. Please specify either 'online' or 'offline' or leave blank."
  exit 1
fi

if [ -z "$1" ]; then
  phase="both"
fi

echo "The phase is $phase."

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

function apt_install ()
{
  local phase=$1
  local python_packages="python3.9=3.9.2-1 python3-pip=20.3.4-4+deb11u1"
  if [ "$phase" == "online" ] || [ "$phase" == "both" ]; then
    echo "online/both"
    apt-get install --reinstall --download-only -y ${python_packages}
    apt-get install -y ${python_packages}
  fi

  if [ "$phase" == "offline" ] || [ "$phase" == "both" ]; then
    echo "offline/both"
    apt-get install -y ${python_packages}
  fi
}

function pip_install ()
{
  local phase=$1
  if [ "$phase" == "online" ] || [ "$phase" == "both" ]; then
    echo "online/both"
    pip3 download -d /var/tmp/downloads --require-hashes -r ${DIR}/pip_requirements.txt
    pip3 install --no-index --find-links /var/tmp/downloads --require-hashes -r ${DIR}/pip_requirements.txt
  fi

  if [ "$phase" == "offline" ] || [ "$phase" == "both" ]; then
    echo "offline/both"
    pip3 install --no-index --find-links /var/tmp/downloads --require-hashes -r ${DIR}/pip_requirements.txt
  fi
}

apt_install $phase
pip_install $phase

echo "Done"
exit 0
