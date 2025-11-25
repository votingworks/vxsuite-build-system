#!/bin/bash
#

set -euo pipefail

action="${1:-status}"

MASS_STORAGE="08:*:*"
KEYBOARD="03:01:*"
MOUSE="03:02:*"

rules_path="/var/etc/usbguard-rules.conf"

if [[ $action == "block" ]]; then
  # generate list of always allowed devices
  usbguard generate-policy | grep -v ${MASS_STORAGE} | grep -v ${KEYBOARD} | grep -v ${MOUSE} > ${rules_path}
  BLOCK_RULES=$(cat <<EOF
# Block external USB storage, keyboards, and mice
block with-interface one-of { ${MASS_STORAGE} }
block with-interface one-of { ${KEYBOARD} }
block with-interface one-of { ${MOUSE} }
EOF
)
  echo "$BLOCK_RULES" >> ${rules_path}
  systemctl restart usbguard
elif [[ $action == "allow" ]]; then
  # generate list of always allowed devices
  usbguard generate-policy | grep -v ${MASS_STORAGE} | grep -v ${KEYBOARD} | grep -v ${MOUSE} > ${rules_path}
  ALLOW_RULES=$(cat <<EOF
# Allow external USB storage, keyboards, and mice
allow with-interface one-of { ${MASS_STORAGE} }
allow with-interface one-of { ${KEYBOARD} }
allow with-interface one-of { ${MOUSE} }
EOF
)
  echo "$ALLOW_RULES" >> ${rules_path}
  systemctl restart usbguard
else
  if grep -q "block with-interface" ${rules_path}; then
    echo "usb blocked"
  else
    echo "usb allowed"
  fi
fi

exit 0
