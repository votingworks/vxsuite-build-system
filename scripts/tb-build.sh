#!/usr/bin/env bash

###
# tb-build.sh – Build VxSuite apps for production.
#
# Builds the requested apps (all of them by default) in place in the vxsuite
# repo, then lays out `vxsuite/build/<app>` with the run scripts and config
# from vxsuite-complete-system plus a `vxsuite` symlink back to the repo.
# setup-machine.sh and run.sh in vxsuite-complete-system consume that layout.
#
#   ./tb-build.sh [all|admin|central-scan|mark|mark-scan|print|scan]...
#
# This runs during the offline phase of a trusted build, so everything it
# needs must already have been fetched by tb-prepare-build.sh.
###

set -euo pipefail

local_user=$(logname)
local_user_home_dir=$( getent passwd "${local_user}" | cut -d: -f6 )
kiosk_browser_dir="${local_user_home_dir}/code/kiosk-browser"
complete_system_dir="${local_user_home_dir}/code/vxsuite-complete-system"
vxsuite_dir="${local_user_home_dir}/code/vxsuite"

# Make sure PATH includes cargo and /sbin
export PATH="${local_user_home_dir}/.cargo/bin:${PATH}:/sbin/"

ALL_APPS=(admin central-scan mark mark-scan print scan)

# Rust daemons that VxMarkScan runs alongside the app. setup-machine.sh picks
# which ones to install (BMD 150 vs 155), so build all of them.
MARK_SCAN_DAEMONS=(accessible-controller pat-device-input fai-100-controller)

usage() {
  echo "usage: ./tb-build.sh [all|$(IFS=\| ; echo "${ALL_APPS[*]}")]..."
  echo
  echo "Build all or some of the VxSuite apps."
}

APPS_TO_BUILD=()

contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "${item}" == "${needle}" ]] && return 0
  done
  return 1
}

if [ $# = 0 ]; then
  APPS_TO_BUILD=("${ALL_APPS[@]}")
else
  for arg in "$@"; do
    if contains "${arg}" "${ALL_APPS[@]}"; then
      if ! contains "${arg}" "${APPS_TO_BUILD[@]}"; then
        APPS_TO_BUILD+=("${arg}")
      fi
    elif [[ "${arg}" = all ]]; then
      APPS_TO_BUILD=("${ALL_APPS[@]}")
    elif [[ "${arg}" = -h || "${arg}" = --help ]]; then
      usage
      exit 0
    else
      echo "✘ unknown app or option: ${arg}" >&2
      usage >&2
      exit 1
    fi
  done
fi

echo "Building ${#APPS_TO_BUILD[@]} app(s): ${APPS_TO_BUILD[*]}"

if ! which kiosk-browser >/dev/null 2>&1
then
  cd "${kiosk_browser_dir}"
  make build
  sudo dpkg -i dist/kiosk-browser_*.deb
fi

# Build every app's frontend and backend in a single turbo run. turbo builds
# their workspace dependencies first and runs independent tasks in parallel.
turbo_filters=()
for app in "${APPS_TO_BUILD[@]}"; do
  turbo_filters+=("--filter=./apps/${app}/frontend" "--filter=./apps/${app}/backend")
done
echo "🔨 Building with turbo"
cd "${vxsuite_dir}"
pnpm exec turbo run build:self "${turbo_filters[@]}"

if contains mark-scan "${APPS_TO_BUILD[@]}"; then
  for daemon in "${MARK_SCAN_DAEMONS[@]}"; do
    echo "🔨 Building mark-scan ${daemon}"
    # Each daemon's Makefile runs ./target/release/<bin>, so build into the
    # crate's own target directory. Crates were fetched while online.
    (cd "${vxsuite_dir}/apps/mark-scan/${daemon}" && cargo build --offline --release --target-dir target)
  done
fi

for app in "${APPS_TO_BUILD[@]}"; do
  echo "📦 Assembling build/${app}"
  build_root="${vxsuite_dir}/build/${app}"
  rm -rf "${build_root}"
  mkdir -p "${build_root}"
  cp -rp \
    "${complete_system_dir}/run-scripts/run-${app}.sh" \
    "${complete_system_dir}/run-scripts/run-kiosk-browser.sh" \
    "${complete_system_dir}/run-scripts/run-kiosk-browser-forever-and-log.sh" \
    "${complete_system_dir}/config" \
    "${complete_system_dir}/app-scripts" \
    "${build_root}"
  # The run scripts expect the built repo at ./vxsuite
  ln -s ../.. "${build_root}/vxsuite"
done

echo -e "\e[32m✅ Built ${APPS_TO_BUILD[*]}\e[0m"
