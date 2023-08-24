#!/usr/bin/env bash

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
  if [ "$phase" == "online" ] || [ "$phase" == "both" ]; then
    echo "online/both"
    apt-get install --reinstall --download-only -y python3.9 python3-pip
    apt-get install -y python3.9 python3-pip
  fi

  if [ "$phase" == "offline" ] || [ "$phase" == "both" ]; then
    echo "offline/both"
    apt-get install -y python3.9 python3-pip
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
