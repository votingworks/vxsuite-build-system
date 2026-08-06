# shellcheck shell=bash
# build-image-vm.sh — helpers for managing the build VM and sending commands
# to it. Sourced, not executed; operates on the caller's globals (VX_NAME,
# BASE_IMAGE, VM_USER, VM_KEY, VM_IP, LIBVIRT_NETWORK, wait-tries constants).
#
# All in-VM work goes through vm_ssh / vm_ssh_tty / vm_script so there is
# exactly one way commands reach the VM — nothing here (or in the caller)
# ever runs build steps on the build server itself.

SSH_OPTS=()

init_vm_ssh() {
  SSH_OPTS=(-i "${VM_KEY}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=5 -o BatchMode=yes -o LogLevel=ERROR)
}

# Run a single command in the VM: vm_ssh "command"
vm_ssh() { ssh "${SSH_OPTS[@]}" "${VM_USER}@${VM_IP}" "$@"; }

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

vm_clone() {
  sudo virt-clone -o "${BASE_IMAGE}" -n "${VX_NAME}" --auto-clone
}

# Install openssh-server, inject our key, set up passwordless sudo, and write
# the /etc/vx-build-vm marker — all on the disk image, before first boot.
# Everything this installs MUST be removed before an image ships; the
# finalize phase does that.
vm_bootstrap_disk() {
  local disk
  disk="$(vm_disk_path "${VX_NAME}")"
  [[ -n "$disk" ]] || die "could not determine disk path for ${VX_NAME}"
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
vm_enable_serial_log() { # $1=log file path
  local xml_tmp rc=0
  xml_tmp="$(mktemp)"
  sudo virsh dumpxml --inactive "${VX_NAME}" > "${xml_tmp}"
  python3 - "${xml_tmp}" "$1" <<'PY' || rc=$?
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

vm_start() {
  if vm_is_running "${VX_NAME}"; then
    log "VM ${VX_NAME} is already running."
    return 0
  fi
  log "Starting ${VX_NAME}..."
  sudo virsh start "${VX_NAME}"
}

# Resolve the VM's IPv4 address into VM_IP, waiting for DHCP.
vm_wait_for_ip() {
  log "Waiting for VM IP address..."
  local mac i
  mac="$(sudo virsh domiflist "${VX_NAME}" | awk 'NR > 2 && $5 ~ /:/ {print $5; exit}')"
  VM_IP=""
  for ((i = 0; i < IP_WAIT_TRIES; i++)); do
    VM_IP="$(sudo virsh domifaddr "${VX_NAME}" 2>/dev/null \
      | awk '/ipv4/ {split($4, a, "/"); print a[1]; exit}')"
    if [[ -z "$VM_IP" && -n "$mac" ]]; then
      # domifaddr's lease lookup misses leases requested with a DUID client-id
      # (which these debian guests use); fall back to matching the domain MAC
      # in the libvirt network's lease table.
      VM_IP="$(sudo virsh net-dhcp-leases "${LIBVIRT_NETWORK}" 2>/dev/null \
        | awk -v mac="$mac" '$3 == mac && $4 == "ipv4" {split($5, a, "/"); print a[1]; exit}')"
    fi
    [[ -n "$VM_IP" ]] && break
    sleep 5
  done
  [[ -n "$VM_IP" ]] \
    || die "VM did not get an IP within $((IP_WAIT_TRIES * 5))s; check: sudo virsh console ${VX_NAME}"
  log "VM IP: ${VM_IP}"
}

vm_wait_for_ssh() {
  log "Waiting for ssh..."
  local i
  for ((i = 0; i < SSH_WAIT_TRIES; i++)); do
    if vm_ssh true 2>/dev/null; then log "ssh is up."; return 0; fi
    sleep 5
  done
  die "could not ssh to ${VM_USER}@${VM_IP}; check: sudo virsh console ${VX_NAME}"
}

# Install the build-remainder script (offline phase + setup-machine +
# build-bootstrap cleanup + self-power-off) into the VM. Expects the
# VM_FINALIZE_* / VM_BUILD_MARKER / VM_NEXT_BOOT_FLAG / VM_SUDOERS_FILE /
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
    >> "\$LOG" 2>&1; then
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
  # The vx-cleanup console drop-in is removed from disk but stays in effect
  # for the imminent shutdown (no daemon-reload), so its output is still
  # captured while the file never ships in the image.
  if apt-get -y purge openssh-server openssh-sftp-server >> "\$LOG" 2>&1 \\
      && rm -rf ${VM_HOME}/.ssh "\$SHIM" /etc/systemd/system/vx-cleanup.service.d \\
      && rm -f ${VM_SUDOERS_FILE} ${VM_BUILD_MARKER} \\
      && touch ${VM_NEXT_BOOT_FLAG}; then
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
vm_ensure_running() {
  vm_exists "${VX_NAME}" || die "VM '${VX_NAME}' does not exist; run without --start-at to create it"
  if ! vm_is_running "${VX_NAME}"; then
    vm_start
  fi
  vm_wait_for_ip
  vm_wait_for_ssh
}
