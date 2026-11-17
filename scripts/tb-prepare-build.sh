#!/usr/bin/env bash

###
# tb-prepare-build.sh – Fetch everything tb-build.sh needs while online.
#
# Runs during the online phase of a trusted build. It installs the vxsuite
# workspace's node modules and fetches all Rust crates so that tb-build.sh can
# run offline.
#
# The vxsuite workspace has a single lockfile, so this prepares every app at
# once; app arguments are accepted for compatibility but have no effect.
###

set -euo pipefail

local_user=$(logname)
local_user_home_dir=$( getent passwd "${local_user}" | cut -d: -f6 )
kiosk_browser_dir="${local_user_home_dir}/code/kiosk-browser"
vxsuite_dir="${local_user_home_dir}/code/vxsuite"

# Make sure PATH includes cargo and /sbin
export PATH="${local_user_home_dir}/.cargo/bin:${PATH}:/sbin/"

cd "${vxsuite_dir}"

echo "Install node modules"
pnpm install --frozen-lockfile

echo "Download all Rust crates"
# The root Cargo workspace covers the mark-scan daemons; the native addons
# outside it fetch their own crates via `install:rust-addon`.
cargo fetch
pnpm --recursive install:rust-addon

if ! which kiosk-browser >/dev/null 2>&1
then
  echo "Download all kiosk-browser tools"
  cd "${kiosk_browser_dir}"
  make install
fi

echo -e "\e[32m✅ Ready for building\e[0m"
