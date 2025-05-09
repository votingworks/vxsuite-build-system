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

if [ ! -d $usb_root ]; then
  mkdir -p $usb_root
fi

if ! mountpoint -q $usb_root; then
  usb_device=$(get_usb_device)
  mount $usb_device $usb_root
fi

#-- Make sure the USB is mounted where we expect
if [ ! -d ${usb_root}/downloads ]; then
  echo "Error: No USB was found at ${usb_root}"
  exit 1;
fi

#-- Set up the various downloads at /var/tmp/downloads/
echo "Copying downloaded tools (Node, Rust, etc...)"
cp -r ${usb_root}/downloads /var/tmp/

#-- Copy all the apt packages to the local cache
echo "Copying apt packages to local cache"
cp -r ${usb_root}/apt_packages/* /var/cache/apt/archives/
#
#-- Copy all the apt lists to the local system
echo "Copying apt lists to local system"
cp -r ${usb_root}/apt_lists/* /var/lib/apt/lists/

if [ ! -d $code_dir ]; then
  mkdir -p $code_dir
  chown ${local_user}:${local_user} $code_dir
fi

#-- Copy vxsuite-complete-system
echo "Copying vxsuite-complete-system code repository"
cp -r ${usb_root}/vxsuite-complete-system $code_dir
chown -R ${local_user}:${local_user} ${code_dir}/vxsuite-complete-system

#-- Copy vxsuite-build-system
echo "Copying vxsuite-build-system code repository"
cp -r ${usb_root}/vxsuite-build-system $code_dir
chown -R ${local_user}:${local_user} ${code_dir}/vxsuite-build-system

#-- Copy cargo packages
echo "Copying cargo crates (Rust)"
if [ ! -d $cargo_dir ]; then
  mkdir -p $cargo_dir
  chown -R ${local_user}:${local_user} ${local_user_home_dir}/.cargo
fi
cp -r ${usb_root}/cargo_packages/* $cargo_dir
chown -R ${local_user}:${local_user} $cargo_dir

#-- Copy pnpm packages
echo "Copying pnpm modules (Node)"
if [ ! -d $pnpm_dir ]; then
  mkdir -p $pnpm_dir
fi
cp -r ${usb_root}/pnpm_packages/* $pnpm_dir
chown -R ${local_user}:${local_user} $pnpm_dir

#-- Copy electron cache
echo "Copying Electron cache and related tools"
if [ ! -d $electron_dir ]; then
  mkdir -p $electron_dir
  chown -R ${local_user}:${local_user} $electron_dir
fi
cp -r ${usb_root}/electron_cache/* $electron_dir
chown -R ${local_user}:${local_user} $electron_dir

#-- Copy electron-gyp cache
if [ ! -d $electron_gyp_dir ]; then
  mkdir -p $electron_gyp_dir
  chown -R ${local_user}:${local_user} $electron_gyp_dir
fi
if [ -d ${usb_root}/electron_gyp_cache ]; then
  cp -r ${usb_root}/electron_gyp_cache/* $electron_gyp_dir
  chown -R ${local_user}:${local_user} $electron_gyp_dir
fi

#-- Copy yarn cache
echo "Copying yarn cache"
if [ ! -d $yarn_dir ]; then
  mkdir -p $yarn_dir
  chown -R ${local_user}:${local_user} $yarn_dir
fi
cp -r ${usb_root}/yarn_cache/* $yarn_dir
chown -R ${local_user}:${local_user} $yarn_dir

echo "All resources required for building have been copied to the correct locations."
echo "Please run: "
echo ""
echo "cd ${code_dir}/vxsuite-build-system && ./scripts/tb-run-offline-phase.sh <inventory name>"
echo ""

exit 0;
