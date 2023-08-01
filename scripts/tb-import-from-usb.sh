#!/usr/bin/env bash

#-- Gonna run as sudo, so we need the local user 
local_user=`logname`
usb_root="/mnt/${local_user}/usb-drive"
local_user_home_dir=$( getent passwd "${local_user}" | cut -d: -f6 )
code_dir="${local_user_home_dir}/code"
cargo_dir="${local_user_home_dir}/.cargo/registry/"
pnpm_dir="${local_user_home_dir}/.local/share/pnpm/"
electron_dir="${local_user_home_dir}/.cache/electron/"
electron_gyp_dir="${local_user_home_dir}/.electron-gyp/"
yarn_dir="${local_user_home_dir}/.cache/yarn/"

function get_usb_device() {
  lsblk /dev/disk/by-id/usb*part* --noheadings --output PATH 2> /dev/null | grep / --max-count 1
}

mkdir -p $usb_root
usb_device=get_usb_device()
mount $usb_device $usb_root

#-- Make sure the USB is mounted where we expect
if [ ! -d ${usb_root}/downloads ]; then
  echo "Error: No USB was found at ${usb_root}"
  exit 1;
fi

#-- Set up the various downloads at /var/tmp/downloads/
cp -r ${usb_root}/downloads /var/tmp/

#-- Copy all the apt packages to the local cache
cp -r ${usb_root}/apt_packages/* /var/cache/apt/archives/

if [ ! -d $code_dir ]; then
  mkdir -p $code_dir
  chown ${local_user}.${local_user} $code_dir
fi

#-- Copy vxsuite-complete-system
cp -r ${usb_root}/vxsuite-complete-system $code_dir
chown -R ${local_user}.${local_user} ${code_dir}/vxsuite-complete-system

#-- Copy vxsuite-build-system
cp -r ${usb_root}/vxsuite-build-system $code_dir
chown -R ${local_user}.${local_user} ${code_dir}/vxsuite-build-system

#-- Copy cargo packages
if [ ! -d $cargo_dir ]; then
  mkdir -p $cargo_dir
  chown -R ${local_user}.${local_user} ${local_user_home_dir}/.cargo
fi
cp -r ${usb_root}/cargo_packages/* $cargo_dir
chown -R ${local_user}.${local_user} $cargo_dir

#-- Copy pnpm packages
if [ ! -d $pnpm_dir ]; then
  mkdir -p $pnpm_dir
fi
cp -r ${usb_root}/pnpm_packages/* $pnpm_dir
chown -R ${local_user}.${local_user} $pnpm_dir

#-- Copy electron cache
if [ ! -d $electron_dir ]; then
  mkdir -p $electron_dir
  chown -R ${local_user}.${local_user} $electron_dir
fi
cp -r ${usb_root}/electron_cache/* $electron_dir
chown -R ${local_user}.${local_user} $electron_dir

#-- Copy electron-gyp cache
if [ ! -d $electron_gyp_dir ]; then
  mkdir -p $electron_gyp_dir
  chown -R ${local_user}.${local_user} $electron_gyp_dir
fi
cp -r ${usb_root}/electron_gyp_cache/* $electron_gyp_dir
chown -R ${local_user}.${local_user} $electron_gyp_dir

#-- Copy yarn cache
if [ ! -d $yarn_dir ]; then
  mkdir -p $yarn_dir
  chown -R ${local_user}.${local_user} $yarn_dir
fi
cp -r ${usb_root}/yarn_cache/* $yarn_dir
chown -R ${local_user}.${local_user} $yarn_dir

exit 0;
