#!/usr/bin/env bash

#-- Gonna run as sudo, so we need the local user 
local_user=`logname`
usb_root="/media/${local_user}/VxTrustedBuild"
local_user_home_dir=$( getent passwd "${local_user}" | cut -d: -f6 )

#-- Make sure the USB is mounted where we expect
if [ ! -d $usb_root ]; then
  echo "Error: No USB was found at ${usb_root}"
  exit 1;
fi

#-- Set up the various downloads at /tmp/downloads/
cp -r ${usb_root}/downloads /tmp/

#-- Copy all the apt packages to the local cache
cp -r ${usb_root}/apt_packages/* /var/cache/apt/archives/

#-- Copy vxsuite-complete-system
cp -r ${usb_root}/vxsuite-complete-system ${local_user_home_dir}/code/
chown -R ${local_user}.${local_user} ${local_user_home_dir}/code/vxsuite-complete-system

exit 0;
