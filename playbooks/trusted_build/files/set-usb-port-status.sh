#!/bin/bash
#

set -euo pipefail

action="${1:-status}"

MASS_STORAGE="08:*:*"
KEYBOARD="03:01:*"
PRINTER="07:*:*"

# Combo keyboard + smartcard reader device (Cherry 046a:00a1)
# We want to be able to use the smartcard reader even with
# the keyboard disabled
# This will be accomplished via sysfs + usbguard config
COMBO_VID="046a"
COMBO_PID="00a1"
COMBO_INTERFACES="03:01:01 03:00:00 0b:00:00"

rules_path="/var/etc/usbguard-rules.conf"

# Set the sysfs "authorized" flag (0/1) on the interfaces of the combo device
set_combo_device_authorized() {
  local state="$1" interface dev
  for interface in /sys/bus/usb/devices/*:*; do
    [[ -e "${interface}/bInterfaceClass" ]] || continue
    dev="${interface%:*}"
    [[ -e "${dev}/idVendor" ]] || continue
    if [[ "$(cat "${dev}/idVendor")" == "${COMBO_VID}" &&
          "$(cat "${dev}/idProduct")" == "${COMBO_PID}" &&
          "$(cat "${interface}/bInterfaceClass")" == "03" ]]; then
      echo "${state}" > "${interface}/authorized"
    fi
  done
}

if [[ $action == "block" ]]; then
  # generate list of always allowed devices
  usbguard generate-policy | grep -v ${MASS_STORAGE} | grep -v ${KEYBOARD} | grep -v ${PRINTER} > ${rules_path}
  BLOCK_RULES=$(cat <<EOF
# Allow the keyboard + smartcard combo
# Its keyboard interfaces are disabled separately via sysfs by this script.
# Must come before the keyboard block rule (first match wins).
allow id ${COMBO_VID}:${COMBO_PID} with-interface equals { ${COMBO_INTERFACES} }
# Block external USB storage, keyboards, and printers
block with-interface one-of { ${MASS_STORAGE} }
block with-interface one-of { ${KEYBOARD} }
block with-interface one-of { ${PRINTER} }
EOF
)
  echo "$BLOCK_RULES" >> ${rules_path}
  systemctl restart usbguard

  # Must run after the restart, which can re-authorize interfaces.
  # The sleep lets usbguard finish applying rules first.
  sleep 2
  set_combo_device_authorized 0
elif [[ $action == "allow" ]]; then
  # Possible TODO: consider a more restrictive policy, but for now we 
  # allow everything so this policy generation is unnecessary
  ALLOW_RULES=$(cat <<EOF
# Allow everything
allow *:*
EOF
)
  echo "$ALLOW_RULES" > ${rules_path}
  systemctl restart usbguard

  # Make sure the keyboard + smartcard combo interfaces are enabled again
  sleep 2
  set_combo_device_authorized 1
else
  if grep -q "block with-interface" ${rules_path}; then
    echo "usb blocked"
  else
    echo "usb allowed"
  fi
fi

exit 0
