#!/usr/bin/env bash

#-- Gonna run as sudo, so we need the local user 
local_user=`logname`
usb_root="/media/${local_user}/VxTrustedBuild"
local_user_home_dir=$( getent passwd "${local_user}" | cut -d: -f6 )
cargo_dir="${local_user_home_dir}/.cargo/registry/"
pnpm_dir="${local_user_home_dir}/.local/share/pnpm/"

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
cp -r ${usb_root}/vxsuite-complete-system ${local_user_home_dir}/code
chown -R ${local_user}.${local_user} ${local_user_home_dir}/code/vxsuite-complete-system

#-- Copy vxsuite-build-system
cp -r ${usb_root}/vxsuite-build-system ${local_user_home_dir}/code
chown -R ${local_user}.${local_user} ${local_user_home_dir}/code/vxsuite-build-system

#-- Copy cargo packages
if [ ! -d $cargo_dir ]; then
  mkdir -p $cargo_dir
fi
cp -r ${usb_root}/cargo_packages/* $cargo_dir
chown -R ${local_user}.${local_user} $cargo_dir

#-- Copy pnpm packages
if [ ! -d $pnpm_dir ]; then
  mkdir -p $pnpm_dir
fi
cp -r ${usb_root}/pnpm_packages/* $pnpm_dir
chown -R ${local_user}.${local_user} $pnpm_dir

exit 0;
