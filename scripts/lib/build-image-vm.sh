# shellcheck shell=bash
# build-image-vm.sh — helpers for managing build VMs and sending commands
# to them. Sourced, not executed; most helpers take the VM name (and IP where
# needed) as arguments; vm_ssh/vm_script target the builder via the caller's
# VM_IP global. Also expects VM_USER, VM_KEY, LIBVIRT_NETWORK, and the
# wait-tries constants from the caller.
#
# All in-VM work goes through vm_ssh / vm_ssh_tty / vm_script so there is
# exactly one way commands reach the VM — nothing here (or in the caller)
# ever runs build steps on the build server itself.

SSH_OPTS=()

init_vm_ssh() {
  SSH_OPTS=(-i "${VM_KEY}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=5 -o BatchMode=yes -o LogLevel=ERROR)
}

# Run a single command in the builder VM (VM_IP global): vm_ssh "command"
vm_ssh() { ssh "${SSH_OPTS[@]}" "${VM_USER}@${VM_IP}" "$@"; }

# Run a single command in an arbitrary VM: vm_ssh_to <ip> "command"
vm_ssh_to() { local _ip="$1"; shift; ssh "${SSH_OPTS[@]}" "${VM_USER}@${_ip}" "$@"; }

# Run a command in the VM with a pty (for scripts that need a login session,
# e.g. anything calling `logname`), streaming output.
vm_ssh_tty() { ssh -tt "${SSH_OPTS[@]}" "${VM_USER}@${VM_IP}" "$@"; }

# Run a multi-line script in the VM, passed on stdin via heredoc:
#   vm_script <<EOF
#   ...commands...
#   EOF
# The heredoc expands on the HOST, so host variables interpolate; escape \$
# for VM-side expansion. `set -euo pipefail` is prepended automatically.
vm_script() {
  { echo 'set -euo pipefail'; cat; } | ssh "${SSH_OPTS[@]}" "${VM_USER}@${VM_IP}" 'bash -s'
}

vm_exists() { sudo virsh dominfo "$1" >/dev/null 2>&1; }

vm_is_running() { [[ "$(sudo virsh domstate "$1" 2>/dev/null)" == "running" ]]; }

vm_disk_path() {
  sudo virsh domblklist "$1" --details | awk '$2 == "disk" {print $4; exit}'
}

vm_delete() { # $1=name — destroy, undefine, and remove disks
  local name="$1" d
  mapfile -t _old_disks < <(sudo virsh domblklist "$name" --details 2>/dev/null \
    | awk '$2 == "disk" {print $4}')
  sudo virsh destroy "$name" 2>/dev/null || true
  sudo virsh undefine --nvram "$name"
  for d in "${_old_disks[@]}"; do
    [[ -f "$d" ]] && sudo rm -f "$d" && log "removed old disk $d"
  done
}

vm_clone() { # $1=source VM  $2=new VM name
  sudo virt-clone -o "$1" -n "$2" --auto-clone
}

# Install openssh-server, inject our key, set up passwordless sudo, and write
# the /etc/vx-build-vm marker — all on the disk image, before first boot.
# Everything this installs MUST be removed before an image ships; the
# finalize phase does that.
vm_bootstrap_disk() { # $1=VM name
  local disk
  disk="$(vm_disk_path "$1")"
  [[ -n "$disk" ]] || die "could not determine disk path for $1"
  # APT-snapshot base images (debian-v*-<date>-bookworm) point at a frozen
  # aptly repo that does NOT carry openssh-server, so temporarily add the
  # upstream Debian archive for the install (ops run in argument order; the
  # extra source is removed again before the image ever boots).
  #
  # Base images created since the preseed change already ship the
  # ${VM_SUDOERS_FILE} NOPASSWD drop-in; write it here only when missing so
  # older bases (e.g. a pre-change debian-latest) keep working. NOPASSWD
  # covers command execution (last matching sudoers rule wins); the tb-*
  # scripts use \`sudo -n true || sudo -v\` so no bare \`sudo -v\` prompts.
  sudo virt-customize -a "${disk}" \
    --write "/etc/apt/sources.list.d/vxbuild-bootstrap.list:deb http://deb.debian.org/debian bookworm main
" \
    --install openssh-server \
    --delete /etc/apt/sources.list.d/vxbuild-bootstrap.list \
    --ssh-inject "${VM_USER}:file:${VM_KEY}.pub" \
    --run-command "test -f ${VM_SUDOERS_FILE} || { echo '${VM_USER} ALL=(ALL) NOPASSWD:ALL' > ${VM_SUDOERS_FILE} && chmod 0440 ${VM_SUDOERS_FILE}; }" \
    --mkdir /etc/systemd/system/vx-cleanup.service.d \
    --write "/etc/systemd/system/vx-cleanup.service.d/zz-vxbuild-console.conf:[Service]
StandardOutput=tty
StandardError=tty
TTYPath=/dev/ttyS0
" \
    --write "/etc/vx-build-vm:build VM created by build-vx-image.sh
"
}

# Point the VM's serial/console device at a host-side log file by inserting
# ONLY a <log> element into the existing domain XML. Deliberately not
# virt-xml: its --edit path re-normalizes the whole domain (reassigning PCI
# addresses), which invalidates the UEFI NVRAM boot entry's device path and
# leaves the clone at the EFI shell instead of booting.
vm_enable_serial_log() { # $1=VM name  $2=log file path
  local xml_tmp rc=0
  xml_tmp="$(mktemp)"
  sudo virsh dumpxml --inactive "$1" > "${xml_tmp}"
  python3 - "${xml_tmp}" "$2" <<'PY' || rc=$?
import sys, xml.etree.ElementTree as ET
path, logfile = sys.argv[1], sys.argv[2]
ET.register_namespace('qemu', 'http://libvirt.org/schemas/domain/qemu/1.0')
ET.register_namespace('libosinfo', 'http://libosinfo.org/xmlns/libvirt/domain/1.0')
tree = ET.parse(path)
devices = tree.getroot().find('devices')
targets = devices.findall('serial') or devices.findall('console')
if not targets:
    sys.exit(3)
for el in targets:
    for old in el.findall('log'):
        el.remove(old)
    ET.SubElement(el, 'log', {'file': logfile, 'append': 'on'})
tree.write(path)
PY
  if [[ "$rc" -eq 0 ]]; then
    sudo virsh define "${xml_tmp}" >/dev/null
  fi
  rm -f "${xml_tmp}"
  return "$rc"
}

vm_start() { # $1=VM name
  if vm_is_running "$1"; then
    log "VM $1 is already running."
    return 0
  fi
  log "Starting $1..."
  sudo virsh start "$1"
}

vm_wait_for_shutoff() { # $1=VM name  $2=tries (x5s)
  local i
  for ((i = 0; i < $2; i++)); do
    vm_is_running "$1" || return 0
    sleep 5
  done
  return 1
}

# Resolve a VM's IPv4 address, waiting for DHCP; echoes the IP (all
# diagnostics go to stderr so command substitution stays clean).
vm_get_ip() { # $1=VM name
  local mac i ip=""
  mac="$(sudo virsh domiflist "$1" | awk 'NR > 2 && $5 ~ /:/ {print $5; exit}')"
  for ((i = 0; i < IP_WAIT_TRIES; i++)); do
    ip="$(sudo virsh domifaddr "$1" 2>/dev/null \
      | awk '/ipv4/ {split($4, a, "/"); print a[1]; exit}')"
    if [[ -z "$ip" && -n "$mac" ]]; then
      # domifaddr's lease lookup misses leases requested with a DUID client-id
      # (which these debian guests use); fall back to matching the domain MAC
      # in the libvirt network's lease table.
      ip="$(sudo virsh net-dhcp-leases "${LIBVIRT_NETWORK}" 2>/dev/null \
        | awk -v mac="$mac" '$3 == mac && $4 == "ipv4" {split($5, a, "/"); print a[1]; exit}')"
    fi
    [[ -n "$ip" ]] && { echo "$ip"; return 0; }
    sleep 5
  done
  die "VM $1 did not get an IP within $((IP_WAIT_TRIES * 5))s; check: sudo virsh console $1"
}

vm_wait_for_ssh() { # $1=ip  $2=VM name (for the error message)
  local i
  for ((i = 0; i < SSH_WAIT_TRIES; i++)); do
    if vm_ssh_to "$1" true 2>/dev/null; then return 0; fi
    sleep 5
  done
  die "could not ssh to ${VM_USER}@$1; check: sudo virsh console $2"
}

# Install the build-remainder script (offline phase + setup-machine +
# build-bootstrap cleanup + self-power-off) into the VM. Expects the
# VM_FINALIZE_* / VM_BUILD_MARKER / VM_SUDOERS_FILE /
# VM_BUILD_SYSTEM_DIR / VM_COMPLETE_SYSTEM_DIR / VM_HOME globals from the
# caller. Configuration values (inventory, machine type, qa flag, vendor
# password) are NOT baked into the file — they arrive via systemd-run
# --setenv at launch.
#
# Launching this as a detached root unit is the host's LAST ssh command:
# everything after runs autonomously in the VM, surviving both the offline
# firewall (which blocks all new inbound connections) and the loss of any
# ssh session. Note: most /home/vx residue (injected key, these status/log
# files) is also wiped by the stock vx-cleanup.service at shutdown; the
# explicit cleanup below covers what that misses (sudoers drop-in, marker,
# the openssh packages) and keeps intent obvious.
vm_install_finalize_script() {
  vm_script <<EOF
sudo tee ${VM_FINALIZE_SCRIPT} >/dev/null <<'UNIT'
#!/bin/bash
# vx-finalize.sh — installed and launched by build-vx-image.sh. Runs as a
# detached root unit inside the build VM ONLY (guarded by the marker file).
set -uo pipefail
STATUS="${VM_FINALIZE_STATUS}"
LOG="${VM_FINALIZE_LOG}"
# mark: record the stage in the status file (host-pollable until the offline
# firewall) AND on the console (qemu logs the serial console to a host-side
# file, surviving the firewall, log cleanup, and power-off).
mark() { echo "\$1" > "\$STATUS"; echo "VX-BUILD: \$1" > /dev/ttyS0 2>/dev/null || true; }
if [[ ! -f ${VM_BUILD_MARKER} ]]; then
  mark "REFUSING: ${VM_BUILD_MARKER} not found — this only runs in build VMs"
  exit 1
fi

# Several build scripts (complete-system build.sh / prepare_build.sh,
# kiosk-browser script/build.sh) call \`logname\`, which fails outside a
# login session. Shim it for the duration of the build; removed in cleanup.
SHIM=/usr/local/lib/vxbuild-shim
mkdir -p "\$SHIM"
printf '#!/bin/sh\necho ${VM_USER}\n' > "\$SHIM/logname"
chmod 755 "\$SHIM/logname"

mark offline-running
if ! runuser -u ${VM_USER} -- env PATH="\$SHIM:\$PATH" VX_INVENTORY="\${VX_INVENTORY}" bash -c \\
    'cd ${VM_BUILD_SYSTEM_DIR} && ./scripts/tb-run-offline-phase.sh "\$VX_INVENTORY"' \\
    2>&1 | tee -a "\$LOG" > /dev/ttyS0; then
  mark offline-failed
  exit 1
fi

mark setup-machine-running
cd ${VM_COMPLETE_SYSTEM_DIR} || { mark setup-machine-failed; exit 1; }
# Translate the unit's configuration (delivered via systemd-run --setenv)
# into setup-machine command line arguments.
SM_ARGS=(--machine-type "\${VX_MACHINE_TYPE}" --skip-scheduled-reboot)
if [[ "\${VX_IS_QA_IMAGE}" == "y" ]]; then SM_ARGS+=(--qa-image); else SM_ARGS+=(--prod-image); fi
[[ "\${VX_IS_RELEASE_IMAGE}" == "y" ]] && SM_ARGS+=(--release-image)
[[ -n "\${VX_VENDOR_PASSWORD:-}" ]] && SM_ARGS+=(--vendor-password "\$VX_VENDOR_PASSWORD")
if runuser -u ${VM_USER} -- env PATH="\$SHIM:\$PATH" \\
    ./setup-machine.sh "\${SM_ARGS[@]}" 2>&1 | tee -a "\$LOG" > /dev/ttyS0; then
  mark cleanup
  # Belt and suspenders: VX_SKIP_SCHEDULED_REBOOT means setup-machine did not
  # schedule its +1 minute reboot (which could otherwise fire before this
  # cleanup finishes), but cancel any scheduled shutdown just in case.
  shutdown -c 2>/dev/null || true
  # Only what vx-cleanup cannot do runs here: the package purge (dpkg during
  # shutdown is unsafe) and this VM's console drop-in for vx-cleanup itself
  # (removed without a daemon-reload so the loaded config still captures the
  # shutdown it is about to run). vx-cleanup removes the build marker, the
  # logname shim, the sudoers drop-in, and everything under /home/vx during
  # that shutdown, so those are not repeated here.
  #
  # The first-boot config wizard flag is not set: vx-iso's flash-image.sh
  # creates it on the target machine at flash time.
  if apt-get -y purge openssh-server openssh-sftp-server >> "\$LOG" 2>&1 \\
      && rm -rf /etc/systemd/system/vx-cleanup.service.d; then
    mark halting
    rm -f ${VM_FINALIZE_SCRIPT} "\$LOG" "\$STATUS"
    sync
    shutdown -h now
  else
    mark cleanup-failed
    exit 1
  fi
else
  mark setup-machine-failed
  exit 1
fi
UNIT
sudo chmod 755 ${VM_FINALIZE_SCRIPT}
EOF
}

# For --start-at resumes: make sure the VM exists and is running, and set
# VM_IP.
vm_ensure_running() { # $1=VM name — sets VM_IP
  vm_exists "$1" || die "VM '$1' does not exist; run without --start-at to create it"
  vm_start "$1"
  VM_IP="$(vm_get_ip "$1")"
  vm_wait_for_ssh "${VM_IP}" "$1"
}
