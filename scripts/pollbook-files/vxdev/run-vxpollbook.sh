#!/bin/bash
export VX_MACHINE_ID=$(cat /vx/config/machine-id)
cd /home/vx/code/vxsuite-complete-system/vxsuite/apps/pollbook/frontend
pnpm start &
sleep 2
cd /home/vx/code/vxsuite-complete-system
./run-scripts/run-kiosk-browser.sh
