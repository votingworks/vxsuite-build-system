#!/bin/bash
#

set -euo pipefail

MASS_STORAGE="08:*:*"
KEYBOARD="03:01:*"
MOUSE="03:02:*"

# generate list of initial allowed devices
usbguard generate-policy | grep -v ${MASS_STORAGE} | grep -v ${KEYBOARD} | grep -v ${MOUSE} > /etc/usbguard/rules.conf

if [[ $1 == "block" ]]; then
  BLOCK_RULES=$(cat <<EOF
# Block external USB storage, keyboards, and mice
block with-interface one-of { ${MASS_STORAGE} }
block with-interface one-of { ${KEYBOARD} }
block with-interface one-of { ${MOUSE} }
EOF
)
  echo "$BLOCK_RULES" >> /etc/usbguard/rules.conf
  systemctl restart usbguard
elif [[ $1 == "allow" ]]; then
  ALLOW_RULES=$(cat <<EOF
# Allow external USB storage, keyboards, and mice
allow with-interface one-of { ${MASS_STORAGE} }
allow with-interface one-of { ${KEYBOARD} }
allow with-interface one-of { ${MOUSE} }
EOF
)
  echo "$ALLOW_RULES" >> /etc/usbguard/rules.conf
  systemctl restart usbguard
else
  if grep -q "allow with-interface" /etc/usbguard/rules.conf; then
    echo "usb allowed"
  else
    echo "usb blocked"
  fi
fi

exit 0
