#!/usr/bin/env bash

# build-vx-image.sh — orchestrates a VxSuite machine-image build.
#
# Runs on the build server. Clones a base Debian VM, bootstraps SSH access
# into the clone, points the chosen inventory at the requested
# vxsuite-complete-system / vxsuite branches, then runs the trusted-build
# phases inside the VM: online, offline, and setup-machine (with build
# bootstrap cleanup), ending with the VM powered off.
#
# Ends with the finished machine VM shut off; with --upload it also
# lz4-compresses the image and uploads it to S3.
#
# Every question — including all of setup-machine's prompts — is asked up
# front, before any phase runs. QA images have defaults for everything.
# setup-machine only ever executes inside the VM (see phase_finalize); no
# build step runs on the build server itself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

# --------------------------------------------------- host-side configuration
VM_KEY="${HOME}/.ssh/vxbuild_ed25519"
LOG_DIR="${HOME}/build-logs"
LIBVIRT_NETWORK="default"
S3_BUCKET="s3://votingworks-machine-images/"

# ----------------------------------------------------- VM-side configuration
VM_USER="vx"
VM_HOME="/home/${VM_USER}"
VM_BUILD_SYSTEM_DIR="${VM_HOME}/code/vxsuite-build-system"
VM_COMPLETE_SYSTEM_DIR="${VM_HOME}/code/vxsuite-complete-system"
VM_SUDOERS_FILE="/etc/sudoers.d/99-vxbuild"
VM_BUILD_MARKER="/etc/vx-build-vm"
VM_FINALIZE_SCRIPT="/usr/local/sbin/vx-finalize.sh"
VM_FINALIZE_STATUS="${VM_HOME}/vx-finalize-status"
VM_FINALIZE_LOG="${VM_HOME}/vx-finalize.log"
VM_NEXT_BOOT_FLAG="/vx/config/RUN_BASIC_CONFIGURATION_ON_NEXT_BOOT"

# --------------------------------------------------------------- build config
BUILD_SYSTEM_BRANCH="caro/one_script_builds"
VALID_APPS=(admin central-scan mark mark-scan print scan)
PHASES=(base clone start prep online offline finalize upload)
IP_WAIT_TRIES=60        # x5s  = 5 minutes
SSH_WAIT_TRIES=36       # x5s  = 3 minutes
OFFLINE_WAIT_TRIES=360   # x20s = 2 hours of status polling (pre-firewall)
FINALIZE_WAIT_TRIES=720  # x10s = 2 hours: offline tail + setup-machine + cleanup after ssh cutoff

# ------------------------------------------------------------------- defaults
INVENTORY="latest"
CS_BRANCH="main"
VX_BRANCH=""
APP=""
IMAGE_TYPE=""
BASE_IMAGE=""
IMAGE_NAME=""
VENDOR_PASSWORD=""
IS_RELEASE=0
CREATE_BASE=0
UPLOAD=0
UPLOADED_TO=""
START_AT=""
ASSUME_YES=0
VM_IP=""

log() { echo "[$(date +%H:%M:%S)] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# Resolve the name a fresh base debian VM will get into BASE_IMAGE,
# following the naming convention of the existing bases
# (<vm_name>-<YYYYMMDD>-<release>, e.g. debian-v4.1.0-20260709-bookworm):
# - inventories that pin an APT snapshot are named by
#   playbooks/virtmanager/create-base-vm.yaml from the snapshot date;
# - inventories without one (e.g. latest) get a creation datestamp via the
#   naming-only base_image_name_suffix variable, which phase_base passes
#   through (BASE_NAME_SUFFIX). A datestamp only affects the name — the
#   base still tracks live apt, unlike a true APT snapshot.
BASE_NAME_SUFFIX=""
resolve_base_image_name() {
  local gv="${REPO_DIR}/inventories/${INVENTORY}/group_vars/all"
  local vm_name snap rel
  vm_name="$(grep -rhoP '^vm_name:\s*"?\K[^"]+' "$gv"/*.y*ml 2>/dev/null | head -1)"
  snap="$(grep -rhoP '^apt_snapshot_date:\s*"?\K[^"]+' "$gv"/*.y*ml 2>/dev/null | head -1 || true)"
  rel="$(grep -rhoP '^release_name:\s*"?\K[^"]+' "$gv"/*.y*ml 2>/dev/null | head -1 || true)"
  [[ -n "$vm_name" ]] || die "could not determine vm_name from inventory '${INVENTORY}'"
  if [[ -n "$snap" && -n "$rel" ]]; then
    BASE_NAME_SUFFIX=""
    BASE_IMAGE="${vm_name}-${snap}-${rel}"
  else
    BASE_NAME_SUFFIX="$(date +%Y%m%d)-${rel:-bookworm}"
    BASE_IMAGE="${vm_name}-${BASE_NAME_SUFFIX}"
  fi
}
# set -e exits are otherwise silent; make sure every failure leaves an
# ERROR line in the log for humans and monitors.
trap 'echo "ERROR: build-vx-image failed at line ${LINENO} (exit $?)" >&2' ERR

# shellcheck source=lib/build-image-args.sh
source "${SCRIPT_DIR}/lib/build-image-args.sh"
# shellcheck source=lib/build-image-vm.sh
source "${SCRIPT_DIR}/lib/build-image-vm.sh"

parse_args "$@"
prompt_for_missing_args
validate_args

if [[ "$IMAGE_TYPE" == "qa" ]]; then QA_YN="y"; else QA_YN="n"; fi
if [[ "$IS_RELEASE" -eq 1 ]]; then RELEASE_YN="y"; else RELEASE_YN="n"; fi
if [[ "$IMAGE_TYPE" == "qa" ]]; then QA_BOOL="true"; else QA_BOOL="false"; fi
# Machine VM naming convention: lowercase, no hyphens in the machine part
# (vxadmin, vxcentralscan, ...), suffixed with the user-provided image name.
VX_NAME="vx${APP//-/}-${IMAGE_NAME}"

mkdir -p "${LOG_DIR}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
MAIN_LOG="${LOG_DIR}/${VX_NAME}-${TIMESTAMP}.log"
BASE_LOG="${LOG_DIR}/${VX_NAME}-${TIMESTAMP}-create-base.log"
CLONE_LOG="${LOG_DIR}/${VX_NAME}-${TIMESTAMP}-clone-bootstrap.log"
ONLINE_LOG="${LOG_DIR}/${VX_NAME}-${TIMESTAMP}-online-phase.log"
OFFLINE_LOG="${LOG_DIR}/${VX_NAME}-${TIMESTAMP}-offline-phase.log"
UPLOAD_LOG="${LOG_DIR}/${VX_NAME}-${TIMESTAMP}-upload.log"
STATE_FILE="${LOG_DIR}/${VX_NAME}.state"
# Everything the guest writes to its serial console lands here (host-side,
# written by qemu) — including boot messages, setup-machine output, and
# vx-cleanup output at shutdown. Survives the offline firewall, the in-VM
# log cleanup, and the final power-off. The path must be under
# /var/log/libvirt/qemu/ for qemu's apparmor profile to allow the write.
SERIAL_LOG="/var/log/libvirt/qemu/${VX_NAME}-serial.log"
# The main output (console + MAIN_LOG) carries only phase progression and
# pointers to the per-phase logs above; verbose phase output goes to those
# logs directly.
exec > >(tee -a "${MAIN_LOG}") 2>&1

record_state() { # $1=key $2=value
  touch "${STATE_FILE}"
  grep -v "^$1=" "${STATE_FILE}" > "${STATE_FILE}.tmp" || true
  echo "$1=$2" >> "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "${STATE_FILE}"
}

log "==================== build-vx-image ===================="
log "inventory:                      ${INVENTORY}"
log "vxsuite-complete-system branch: ${CS_BRANCH}"
log "vxsuite branch override:        ${VX_BRANCH:-<none>}"
log "app:                            ${APP}"
log "image type:                     ${IMAGE_TYPE} (release: ${RELEASE_YN})"
if [[ "$CREATE_BASE" -eq 1 ]]; then
  log "base image:                     ${BASE_IMAGE} (will be created)"
else
  log "base image:                     ${BASE_IMAGE}"
fi
log "VM name:                        ${VX_NAME}"
log "compress + upload:              $([[ "$UPLOAD" -eq 1 ]] && echo "yes (${S3_BUCKET})" || echo no)"
log "start at phase:                 ${START_AT:-clone (full run)}"
log "log file:                       ${MAIN_LOG}"
log "========================================================="

if [[ "$ASSUME_YES" -ne 1 && -t 0 ]]; then
  read -rp "Proceed? [y/N]: " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || die "aborted"
fi

init_vm_ssh
for key in INVENTORY CS_BRANCH VX_BRANCH APP IMAGE_TYPE BASE_IMAGE BUILD_SYSTEM_BRANCH; do
  record_state "$key" "${!key}"
done

# Returns success if the given phase should run under --start-at.
should_run() {
  [[ -z "$START_AT" ]] && return 0
  local i idx=0 start_idx=0
  for i in "${!PHASES[@]}"; do
    [[ "${PHASES[$i]}" == "$1" ]] && idx=$i
    [[ "${PHASES[$i]}" == "$START_AT" ]] && start_idx=$i
  done
  ((idx >= start_idx))
}

# ------------------------------------------------------------------ phases

# Create a fresh base debian VM for the inventory via the existing
# tb-initialize-build-machine.sh (virt-install + preseed; the VM is left
# powered off, which is exactly what virt-clone wants). Runs on the build
# server — base creation is host-side by nature; it is the one step that
# does not touch a build VM.
phase_base() {
  [[ "$CREATE_BASE" -eq 1 ]] || return 0
  if vm_exists "$BASE_IMAGE"; then
    echo "A base VM named '${BASE_IMAGE}' already exists."
    if [[ "$ASSUME_YES" -eq 1 || ! -t 0 ]]; then
      die "refusing to delete existing base VM non-interactively; remove it first:
  sudo virsh undefine --nvram ${BASE_IMAGE}; sudo rm /var/lib/libvirt/images/${BASE_IMAGE}.img
or drop --create-base-image to build from the existing one"
    fi
    read -rp "Delete it and its disk image? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || die "aborted; existing base VM left in place"
    vm_delete "$BASE_IMAGE"
  fi
  log "Creating base debian image '${BASE_IMAGE}' for inventory '${INVENTORY}' (netinst + preseed; 15-30 minutes)..."
  log "  log: ${BASE_LOG}"
  local extra_args=()
  [[ -n "$BASE_NAME_SUFFIX" ]] \
    && extra_args+=(-e "base_image_name_suffix=${BASE_NAME_SUFFIX}")
  (cd "${REPO_DIR}" && ./scripts/tb-initialize-build-machine.sh "${INVENTORY}" "${extra_args[@]}") \
    >> "${BASE_LOG}" 2>&1 \
    || die "base image creation FAILED; see ${BASE_LOG}"
  vm_exists "$BASE_IMAGE" \
    || die "base image creation finished but VM '${BASE_IMAGE}' was not found; check ${BASE_LOG}"
  log "Base image '${BASE_IMAGE}' created."
  record_state PHASE_base "$(date +%s)"
}

phase_clone() {
  if vm_exists "$VX_NAME"; then
    echo "A VM named '${VX_NAME}' already exists."
    if [[ "$ASSUME_YES" -eq 1 || ! -t 0 ]]; then
      die "refusing to delete existing VM non-interactively; remove it first:
  sudo virsh destroy ${VX_NAME}; sudo virsh undefine --nvram ${VX_NAME}
or resume it with --start-at"
    fi
    read -rp "Delete it and its disk image? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || die "aborted; existing VM left in place"
    vm_delete "$VX_NAME"
  fi
  log "Cloning ${BASE_IMAGE} -> ${VX_NAME} (disk copy; can take several minutes)..."
  log "  log: ${CLONE_LOG}"
  vm_clone >> "${CLONE_LOG}" 2>&1
  log "Bootstrapping VM disk (sshd + key + sudoers + marker)..."
  vm_bootstrap_disk >> "${CLONE_LOG}" 2>&1
  # Log the guest's serial console to a host-side file: this captures boot
  # messages, setup-machine output, and vx-cleanup output at shutdown —
  # even after the offline firewall blocks ssh. Non-fatal on failure; the
  # build works without it, just with less visibility.
  if vm_enable_serial_log "${SERIAL_LOG}" >> "${CLONE_LOG}" 2>&1; then
    log "  serial console log: ${SERIAL_LOG}"
  else
    log "WARNING: could not enable serial console logging (see ${CLONE_LOG}); continuing without it"
    SERIAL_LOG=""
  fi
  record_state PHASE_clone "$(date +%s)"
}

phase_start() {
  vm_start
  vm_wait_for_ip
  vm_wait_for_ssh
  record_state PHASE_start "$(date +%s)"
  record_state VM_IP "${VM_IP}"
}

phase_prep() {
  log "Updating vxsuite-build-system in the VM (branch: ${BUILD_SYSTEM_BRANCH})..."
  vm_script <<EOF
cd ${VM_BUILD_SYSTEM_DIR}
git fetch origin
git checkout ${BUILD_SYSTEM_BRANCH}
git pull --ff-only origin ${BUILD_SYSTEM_BRANCH}
echo "build-system now at: \$(git rev-parse --short HEAD) (\$(git branch --show-current))"
EOF

  log "Updating inventory '${INVENTORY}' in the VM..."
  vm_script <<EOF
f="${VM_BUILD_SYSTEM_DIR}/inventories/${INVENTORY}/group_vars/all/main.yaml"
[[ -f "\$f" ]] || { echo "ERROR: \$f not found in VM" >&2; exit 1; }

# Point vxsuite-complete-system at the requested branch (the version line
# immediately following the 'vxsuite-complete-system:' key).
sed -i '/vxsuite-complete-system:/{n;s|version:.*|version: "${CS_BRANCH}"|}' "\$f"

# Set or clear the vxsuite override.
sed -i '/^vxsuite_version_override:/d' "\$f"
if [[ -n "${VX_BRANCH}" ]]; then
  printf 'vxsuite_version_override: "%s"\n' '${VX_BRANCH}' >> "\$f"
fi

# QA vs prod (not all inventories define the key, e.g. v4.1.0).
if grep -q '^qa_image:' "\$f"; then
  sed -i 's/^qa_image:.*/qa_image: ${QA_BOOL}/' "\$f"
else
  printf 'qa_image: %s\n' '${QA_BOOL}' >> "\$f"
fi

echo "--- ${INVENTORY} inventory main.yaml after edits ---"
cat "\$f"
EOF

  # The finalize script must be installed BEFORE the offline phase: the
  # offline firewalld playbook sets the default zone to drop, after which no
  # NEW ssh connection to the VM can be opened (only the already-established
  # offline session keeps working).
  vm_ssh "test -f ${VM_BUILD_MARKER}" \
    || die "refusing to stage finalize: ${VM_BUILD_MARKER} missing in VM — not a build VM this script created?"
  log "Installing finalize script in the VM (must happen before the offline firewall)..."
  vm_install_finalize_script
  record_state PHASE_prep "$(date +%s)"
}

phase_online() {
  log "Running the online phase in the VM (typically ~20 minutes)..."
  log "  log: ${ONLINE_LOG}  (tail -f to watch)"
  # -tt: the tb-* scripts use \`logname\`, which needs a login session.
  local started="$SECONDS"
  vm_ssh_tty "cd ${VM_BUILD_SYSTEM_DIR} && ./scripts/tb-run-online-phase.sh ${INVENTORY}" \
    >> "${ONLINE_LOG}" 2>&1 \
    || die "online phase FAILED; see ${ONLINE_LOG}"
  log "Online phase completed in $(((SECONDS - started) / 60))m."
  record_state PHASE_online "$(date +%s)"
}

# Launch the build-remainder unit (offline phase + setup-machine + cleanup +
# self-power-off) as the LAST ssh command the host ever sends, then poll its
# status file while ssh still works. The offline firewalld playbook drops
# all new inbound connections partway through, at which point polling stops
# and phase_finalize falls back to watching the VM's power state. Running
# the remainder detached (rather than through a held ssh session) means a
# 60+ minute build can't be killed by an ssh hiccup.
phase_offline() {
  log "Launching build-remainder unit (offline phase + setup-machine + cleanup)..."
  local launch_cmd a
  launch_cmd="sudo systemd-run --unit=vx-finalize"
  local setenv_args=(
    "--setenv=VX_INVENTORY=${INVENTORY}"
    "--setenv=VX_MACHINE_TYPE=${APP}"
    "--setenv=VX_IS_QA_IMAGE=${QA_YN}"
    "--setenv=VX_IS_RELEASE_IMAGE=${RELEASE_YN}"
  )
  [[ -n "$VENDOR_PASSWORD" ]] && setenv_args+=("--setenv=VX_VENDOR_PASSWORD=${VENDOR_PASSWORD}")
  for a in "${setenv_args[@]}"; do launch_cmd+=" $(printf '%q' "$a")"; done
  launch_cmd+=" ${VM_FINALIZE_SCRIPT}"
  vm_ssh "$launch_cmd" >> "${OFFLINE_LOG}" 2>&1
  record_state PHASE_offline "$(date +%s)"
  log "  in-VM log (snapshotted while ssh lasts): ${OFFLINE_LOG}"
  [[ -n "$SERIAL_LOG" ]] && log "  full record incl. post-firewall: ${SERIAL_LOG}"

  local i ssh_dead=0 st last_st=""
  for ((i = 0; i < OFFLINE_WAIT_TRIES; i++)); do
    if st="$(vm_ssh "cat ${VM_FINALIZE_STATUS} 2>/dev/null || echo pending" 2>/dev/null)"; then
      ssh_dead=0
      if [[ "$st" != "$last_st" ]]; then
        log "build-remainder stage: ${st}"
        last_st="$st"
      fi
      # Snapshot the in-VM log so we keep a copy even after the VM wipes it.
      vm_ssh "cat ${VM_FINALIZE_LOG} 2>/dev/null" > "${OFFLINE_LOG}" 2>/dev/null || true
      case "$st" in
        offline-failed|setup-machine-failed|cleanup-failed|REFUSING*)
          die "build-remainder unit reported '${st}'; debug via: ssh -i ${VM_KEY} ${VM_USER}@${VM_IP} (if reachable) or sudo virsh console ${VX_NAME}  (see ${OFFLINE_LOG})" ;;
      esac
    else
      ((++ssh_dead))
      if ((ssh_dead >= 3)); then
        log "ssh unreachable (offline firewall is up); switching to power-state watch."
        return 0
      fi
    fi
    sleep 20
  done
  die "build-remainder unit still in state '${st:-unknown}' after $((OFFLINE_WAIT_TRIES * 20 / 60)) minutes"
}

# Watch the finalize unit (launched at the end of phase_offline) run
# setup-machine and the build-bootstrap cleanup, ending with the VM powering
# itself off. The unit:
#   1. runs setup-machine as the vx user, answers provided via environment
#      variables (VX_MACHINE_TYPE et al., supported on the complete-system
#      branch caro/one_script_builds)
#   2. on success: cancels setup-machine's scheduled reboot, purges
#      openssh-server, removes the injected key + sudoers drop-in + marker,
#      sets the config-wizard-on-next-boot flag, and powers off. vm-fstrim
#      runs during that shutdown (it is hooked to shutdown.target), and no
#      further boot happens that could consume the config-wizard flag.
#   3. on failure: leaves everything in place and the VM running.
#
# By this point the offline firewall drops all new inbound connections, so
# the host can only observe the VM's power state: shut off = success;
# still running past the timeout = failure (debug via virsh console).
phase_finalize() {
  log "Watching finalize (offline tail + setup-machine + cleanup); success = VM powers itself off..."
  if [[ -n "$SERIAL_LOG" ]]; then
    log "  stage markers and full output: ${SERIAL_LOG}  (sudo tail -f to watch)"
  else
    log "  (no serial log; progress only visible via: sudo virsh console ${VX_NAME})"
  fi
  local i seen=0 total m markers
  for ((i = 0; i < FINALIZE_WAIT_TRIES; i++)); do
    # Relay any new stage markers the in-VM unit wrote to the serial console.
    if [[ -n "$SERIAL_LOG" ]]; then
      total="$(sudo grep -ac 'VX-BUILD:' "${SERIAL_LOG}" 2>/dev/null)" || total=0
      if ((total > seen)); then
        mapfile -t markers < <(sudo grep -a 'VX-BUILD:' "${SERIAL_LOG}" 2>/dev/null | tail -n "$((total - seen))")
        for m in "${markers[@]}"; do log "  ${m#*VX-BUILD: }"; done
        seen="$total"
      fi
    fi
    if ! vm_is_running "$VX_NAME"; then
      log "VM has powered off — setup-machine and cleanup completed."
      record_state PHASE_finalize "$(date +%s)"
      return 0
    fi
    sleep 10
  done
  die "VM did not power off within $((FINALIZE_WAIT_TRIES * 10 / 60)) minutes.
setup-machine or the bootstrap cleanup likely failed; inspect via:
  sudo virsh console ${VX_NAME}   (vx/votingworks; check ${VM_FINALIZE_STATUS} and ${VM_FINALIZE_LOG})
  ${SERIAL_LOG:+or the serial log: ${SERIAL_LOG}}"
}

# lz4-compress the finished image and upload it to S3, following the manual
# process (image name prefixed with the date for bookkeeping). Only runs
# with --upload; requires the VM to be shut off (i.e. finalize completed).
phase_upload() {
  [[ "$UPLOAD" -eq 1 ]] || return 0
  vm_is_running "$VX_NAME" \
    && die "refusing to compress a running VM; wait for finalize to power it off"
  local disk archive
  disk="$(vm_disk_path "${VX_NAME}")"
  [[ -n "$disk" ]] || die "could not determine disk path for ${VX_NAME}"
  archive="${HOME}/$(date +%Y-%m-%d)-${IMAGE_NAME}-vx${APP//-/}.img.lz4"
  [[ -e "$archive" ]] \
    && die "archive ${archive} already exists; remove it or rename the image"
  log "Compressing ${disk} -> ${archive} (this takes several minutes)..."
  log "  log: ${UPLOAD_LOG}"
  sudo lz4 "${disk}" "${archive}" >> "${UPLOAD_LOG}" 2>&1 \
    || die "lz4 compression FAILED; see ${UPLOAD_LOG}"
  log "Uploading $(basename "${archive}") to ${S3_BUCKET}..."
  sudo aws s3 cp "${archive}" "${S3_BUCKET}" >> "${UPLOAD_LOG}" 2>&1 \
    || die "S3 upload FAILED; see ${UPLOAD_LOG}. The local archive is kept at ${archive}"
  UPLOADED_TO="${S3_BUCKET}$(basename "${archive}")"
  log "Uploaded: ${UPLOADED_TO}"
  record_state PHASE_upload "$(date +%s)"
  record_state UPLOADED_TO "${UPLOADED_TO}"
}

# --------------------------------------------------------------------- run
should_run base    && phase_base
should_run clone   && phase_clone
should_run start   && phase_start
case "$START_AT" in
  prep|online|offline)
    # Resuming into a phase that needs a live ssh channel.
    vm_ensure_running ;;
  finalize|upload)
    # Resuming into watch-only or compress/upload (no ssh needed); the VM
    # just needs to exist.
    vm_exists "$VX_NAME" || die "VM '${VX_NAME}' does not exist" ;;
esac
should_run prep     && phase_prep
should_run online   && phase_online
should_run offline  && phase_offline
should_run finalize && phase_finalize
[[ "$START_AT" == "upload" ]] && UPLOAD=1   # resuming into upload implies it
should_run upload   && phase_upload

DISK_PATH="$(vm_disk_path "${VX_NAME}")"
log "========================================================="
if [[ "$UPLOAD" -eq 1 ]]; then
  log "DONE — image built, compressed, and uploaded."
else
  log "DONE (compress/upload skipped; pass --upload to include them)."
fi
log ""
log "Machine VM '${VX_NAME}' (${APP}, ${IMAGE_TYPE}) is built and shut off."
log "  disk image:      ${DISK_PATH}"
log "  state:           ${STATE_FILE}"
log "  main log:        ${MAIN_LOG}"
[[ "$CREATE_BASE" -eq 1 ]] \
  && log "  base creation:   ${BASE_LOG}"
log "  clone/bootstrap: ${CLONE_LOG}"
log "  online phase:    ${ONLINE_LOG}"
log "  offline phase:   ${OFFLINE_LOG} (in-VM snapshot until firewall)"
[[ -n "$SERIAL_LOG" ]] \
  && log "  serial console:  ${SERIAL_LOG} (boot + setup-machine + vx-cleanup output)"
log ""
log "Build bootstrap has been removed from the image:"
log "  - openssh-server purged"
log "  - ${VM_HOME}/.ssh removed"
log "  - ${VM_SUDOERS_FILE} removed"
log "  - config wizard will run on first boot (${VM_NEXT_BOOT_FLAG})"
log ""
if [[ "$UPLOAD" -eq 1 ]]; then
  log "Uploaded image: ${UPLOADED_TO}"
  log "  upload log:   ${UPLOAD_LOG}"
else
  log "To compress and upload later:"
  log "  rerun with:   --start-at upload  (plus the same --app/--name)"
  log "  or manually:  sudo lz4 ${DISK_PATH} ~/$(date +%Y-%m-%d)-${IMAGE_NAME}-vx${APP//-/}.img.lz4"
  log "                sudo aws s3 cp ~/$(date +%Y-%m-%d)-${IMAGE_NAME}-vx${APP//-/}.img.lz4 ${S3_BUCKET}"
fi
