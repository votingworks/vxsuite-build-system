#!/usr/bin/env bash

set -euo pipefail

# go to directory where this file is located
cd "$(dirname "$0")"

# configuration information
CONFIG=${VX_CONFIG_ROOT:-./config}
METADATA=${VX_METADATA_ROOT:-./}
source ${CONFIG}/read-vx-machine-config.sh
export CACVOTE_MARK_WORKSPACE="/vx/data/cacvote-mark-workspace"

cd cacvote/apps/cacvote-mark/
(trap 'kill 0' SIGINT SIGHUP; make -C backend run & cd frontend/prodserver && node index.js)
