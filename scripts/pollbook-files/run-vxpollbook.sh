#!/usr/bin/env bash

set -euo pipefail

# go to directory where this file is located
cd "$(dirname "$0")"

# configuration information
CONFIG=${VX_CONFIG_ROOT:-./config}
METADATA=${VX_METADATA_ROOT:-./}
source ${CONFIG}/read-vx-machine-config.sh

if [ -z "${WORKSPACE:-}" ]; then
  echo "error: please set WORKSPACE and try again" >&2
  exit 1
fi

export PIPENV_VENV_IN_PROJECT=1
export NODE_ENV=production
(trap 'kill 0' SIGINT SIGHUP; make -C vxpollbook/apps/pollbook/backend run & make -C vxpollbook/apps/pollbook/frontend run) | logger -S 4096 --tag votingworksapp
