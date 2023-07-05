#!/usr/bin/env bash

# If no phase, we should just do ALL THE THINGS
# Dont worry about it yet
# Check if the phase argument was passed

# Get the phase
phase=$1

if [ "$phase" != "online" ] && [ "$phase" != "offline" ] && [ "$phase" != "" ]; then
  echo "Error: Invalid phase. Please specify either 'online' or 'offline' or leave blank."
  exit 1
fi

if [ -z "$1" ]; then
  phase="both"
fi

# Print a message indicating the phase
echo "The phase is $phase."

function apt_install ()
{
  local phase=$1
  if [ "$phase" == "online" ] || [ "$phase" == "both" ]; then
    echo "online/both"
    apt-get install --reinstall --download-only -y python3.9 python3-pip
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
    pip3 download -d /tmp/downloads ansible passlib pipenv 
  fi

  if [ "$phase" == "offline" ] || [ "$phase" == "both" ]; then
    echo "offline/both"
    pip3 install --no-index --find-links /tmp/downloads ansible passlib pipenv
  fi
}

apt_install $phase
pip_install $phase

echo "Done"
exit 0
