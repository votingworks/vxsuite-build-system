#!/usr/bin/env bash

#-- Gonna run as sudo, so we need the local user 
local_user=`logname`
usb_root="/media/${local_user}/VxTrustedBuild"

#-- Make sure the USB is mounted where we expect
if [ ! -d $usb_root ]; then
  echo "Error: No USB was found at ${usb_root}"
  exit 1;
fi

#-- Set up the various downloads at /tmp/downloads/
cp -r ${usb_root}/downloads /tmp/

#-- Copy all the apt packages to the local cache
cp -r ${usb_root}/apt_packages/* /var/cache/apt/archives/

exit 0;
