#!/usr/bin/env bash

set -euo pipefail

# go to directory where this file is located
cd "$(dirname "$0")"

# configuration information
CONFIG=${VX_CONFIG_ROOT:-./config}
METADATA=${VX_METADATA_ROOT:-./}
source ${CONFIG}/read-vx-machine-config.sh

# hardcoding for now
export PORT=3000
export PUBLIC_DIR=./public

cd cacvote/apps/cacvote-jx-terminal/dist
(trap 'kill 0' SIGINT SIGHUP; ./cacvote-jx-terminal)
