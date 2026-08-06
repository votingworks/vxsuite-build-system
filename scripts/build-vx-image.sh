#!/usr/bin/env bash

# build-vx-image.sh — orchestrates VxSuite machine-image builds.
#
# Runs on the build server. Optionally creates a base Debian VM, then:
#   1. clones the base into a BUILDER VM (vx-<name>), bootstraps it (ssh +
#      passwordless sudo + build marker), points the chosen inventory at the
#      requested vxsuite-complete-system / vxsuite branches, and runs the
#      online phase in it;
#   2. shuts the builder down and clones it once per requested app
#      (vxadmin-<name>, vxmark-<name>, ...) — the clone point must be before
#      the offline phase, whose firewall makes VMs permanently unreachable
#      over the network;
#   3. hands each app VM a detached systemd unit that runs the offline
#      phase, setup-machine, build-bootstrap cleanup, and self-power-off —
#      all app VMs proceed in PARALLEL;
#   4. with --upload, lz4-compresses each finished image and uploads it
#      to S3.
#
# The builder VM is kept (shut off) so more app types can be cloned from it
# later; remove it with cleanup-vx-build.sh when done.
#
# Every question — including all of setup-machine's prompts — is asked up
# front, before any phase runs. QA images have defaults for everything.
# setup-machine only ever executes inside app VMs; no build step runs on
# the build server itself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

# --------------------------------------------------- host-side configuration
VM_KEY="${HOME}/.ssh/vxbuild_ed25519"
LOG_DIR="${HOME}/build-logs"
LIBVIRT_NETWORK="default"
S3_BUCKET="s3://votingworks-machine-images/"
SERIAL_LOG_DIR="/var/log/libvirt/qemu"

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
PHASES=(base clone start prep online appclone finalize upload)
IP_WAIT_TRIES=60         # x5s  = 5 minutes
SSH_WAIT_TRIES=36        # x5s  = 3 minutes
SHUTOFF_WAIT_TRIES=60    # x5s  = 5 minutes for the builder to shut down
FINALIZE_WAIT_TRIES=480  # x15s = 2 hours: offline + setup-machine + cleanup

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
START_AT=""
ASSUME_YES=0
VM_IP=""
APPS=()

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

# Naming: one builder VM per image name, one app VM per requested app
# (lowercase, no hyphens in the machine part, per convention).
BUILDER="vx-${IMAGE_NAME}"
APP_VMS=()
for _app in "${APPS[@]}"; do APP_VMS+=("vx${_app//-/}-${IMAGE_NAME}"); done
declare -A APP_VM_IP=()

serial_log_for() { echo "${SERIAL_LOG_DIR}/$1-serial.log"; }

mkdir -p "${LOG_DIR}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
MAIN_LOG="${LOG_DIR}/${BUILDER}-${TIMESTAMP}.log"
BASE_LOG="${LOG_DIR}/${BUILDER}-${TIMESTAMP}-create-base.log"
CLONE_LOG="${LOG_DIR}/${BUILDER}-${TIMESTAMP}-clone-bootstrap.log"
ONLINE_LOG="${LOG_DIR}/${BUILDER}-${TIMESTAMP}-online-phase.log"
UPLOAD_LOG="${LOG_DIR}/${BUILDER}-${TIMESTAMP}-upload.log"
STATE_FILE="${LOG_DIR}/${BUILDER}.state"
remainder_log_for() { echo "${LOG_DIR}/$1-${TIMESTAMP}-remainder.log"; }
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
log "apps:                           ${APPS[*]}"
log "image type:                     ${IMAGE_TYPE} (release: ${RELEASE_YN})"
if [[ "$CREATE_BASE" -eq 1 ]]; then
  log "base image:                     ${BASE_IMAGE} (will be created)"
else
  log "base image:                     ${BASE_IMAGE}"
fi
log "builder VM:                     ${BUILDER}"
log "app VMs:                        ${APP_VMS[*]}"
log "compress + upload:              $([[ "$UPLOAD" -eq 1 ]] && echo "yes (${S3_BUCKET})" || echo no)"
log "start at phase:                 ${START_AT:-clone (full run)}"
log "log file:                       ${MAIN_LOG}"
log "========================================================="

if [[ "$ASSUME_YES" -ne 1 && -t 0 ]]; then
  read -rp "Proceed? [y/N]: " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || die "aborted"
fi

init_vm_ssh
record_state INVENTORY "${INVENTORY}"
record_state CS_BRANCH "${CS_BRANCH}"
record_state VX_BRANCH "${VX_BRANCH}"
record_state APPS "${APPS[*]}"
record_state IMAGE_TYPE "${IMAGE_TYPE}"
record_state BASE_IMAGE "${BASE_IMAGE}"
record_state BUILD_SYSTEM_BRANCH "${BUILD_SYSTEM_BRANCH}"

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

# Interactive-or-die guard for deleting an existing VM.
confirm_delete_vm() { # $1=VM name  $2=hint for the non-interactive error
  vm_exists "$1" || return 0
  echo "A VM named '$1' already exists."
  if [[ "$ASSUME_YES" -eq 1 || ! -t 0 ]]; then
    die "refusing to delete existing VM non-interactively; remove it first:
  ./scripts/cleanup-vx-build.sh $1
$2"
  fi
  read -rp "Delete it and its disk image? [y/N]: " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || die "aborted; existing VM left in place"
  vm_delete "$1"
}

# The systemd-run command that starts the build-remainder unit for one app.
build_launch_cmd() { # $1=app
  local cmd="sudo systemd-run --unit=vx-finalize" a
  local setenv_args=(
    "--setenv=VX_INVENTORY=${INVENTORY}"
    "--setenv=VX_MACHINE_TYPE=$1"
    "--setenv=VX_IS_QA_IMAGE=${QA_YN}"
    "--setenv=VX_IS_RELEASE_IMAGE=${RELEASE_YN}"
  )
  [[ -n "$VENDOR_PASSWORD" ]] && setenv_args+=("--setenv=VX_VENDOR_PASSWORD=${VENDOR_PASSWORD}")
  for a in "${setenv_args[@]}"; do cmd+=" $(printf '%q' "$a")"; done
  cmd+=" ${VM_FINALIZE_SCRIPT}"
  echo "$cmd"
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
      die "refusing to delete existing base VM non-interactively; remove it first
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
  confirm_delete_vm "$BUILDER" "or resume it with --start-at"
  log "Cloning ${BASE_IMAGE} -> ${BUILDER} (disk copy; can take several minutes)..."
  log "  log: ${CLONE_LOG}"
  vm_clone "${BASE_IMAGE}" "${BUILDER}" >> "${CLONE_LOG}" 2>&1
  log "Bootstrapping builder disk (sshd + key + sudoers + marker)..."
  vm_bootstrap_disk "${BUILDER}" >> "${CLONE_LOG}" 2>&1
  # Log the guest's serial console to a host-side file: this captures boot
  # messages and stage markers even after the offline firewall blocks ssh.
  # Non-fatal on failure; the build works without it.
  if vm_enable_serial_log "${BUILDER}" "$(serial_log_for "${BUILDER}")" >> "${CLONE_LOG}" 2>&1; then
    log "  serial console log: $(serial_log_for "${BUILDER}")"
  else
    log "WARNING: could not enable serial console logging for ${BUILDER} (see ${CLONE_LOG})"
  fi
  record_state PHASE_clone "$(date +%s)"
}

phase_start() {
  vm_start "${BUILDER}"
  log "Waiting for builder IP address..."
  VM_IP="$(vm_get_ip "${BUILDER}")"
  log "Builder IP: ${VM_IP}"
  log "Waiting for ssh..."
  vm_wait_for_ssh "${VM_IP}" "${BUILDER}"
  log "ssh is up."
  record_state PHASE_start "$(date +%s)"
  record_state BUILDER_IP "${VM_IP}"
}

phase_prep() {
  log "Updating vxsuite-build-system in the builder (branch: ${BUILD_SYSTEM_BRANCH})..."
  vm_script <<EOF
cd ${VM_BUILD_SYSTEM_DIR}
git fetch origin
git checkout ${BUILD_SYSTEM_BRANCH}
git pull --ff-only origin ${BUILD_SYSTEM_BRANCH}
echo "build-system now at: \$(git rev-parse --short HEAD) (\$(git branch --show-current))"
EOF

  log "Updating inventory '${INVENTORY}' in the builder..."
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

  # The finalize script must be installed BEFORE the app clones are made:
  # it rides the builder image into every clone, and the offline firewall
  # each clone raises makes later installation impossible.
  vm_ssh "test -f ${VM_BUILD_MARKER}" \
    || die "refusing to stage finalize: ${VM_BUILD_MARKER} missing in VM — not a build VM this script created?"
  log "Installing finalize script in the builder (inherited by all app clones)..."
  vm_install_finalize_script
  record_state PHASE_prep "$(date +%s)"
}

phase_online() {
  log "Running the online phase in the builder (typically ~20 minutes)..."
  log "  log: ${ONLINE_LOG}  (tail -f to watch)"
  # -tt: the tb-* scripts use \`logname\`, which needs a login session.
  local started="$SECONDS"
  vm_ssh_tty "cd ${VM_BUILD_SYSTEM_DIR} && ./scripts/tb-run-online-phase.sh ${INVENTORY}" \
    >> "${ONLINE_LOG}" 2>&1 \
    || die "online phase FAILED; see ${ONLINE_LOG}"
  log "Online phase completed in $(((SECONDS - started) / 60))m."
  record_state PHASE_online "$(date +%s)"
}

# Shut the builder down and clone it once per app, launching each app's
# detached build-remainder unit (offline phase + setup-machine + cleanup +
# self-power-off) as soon as that clone is reachable. Clones are made
# sequentially (disk copies contend for IO); the remainder units all run in
# parallel.
phase_appclone() {
  if vm_is_running "${BUILDER}"; then
    if [[ -z "${VM_IP}" ]]; then
      VM_IP="$(vm_get_ip "${BUILDER}")"
      vm_wait_for_ssh "${VM_IP}" "${BUILDER}"
    fi
    log "Shutting down the builder before cloning..."
    vm_ssh "sudo shutdown -h now" 2>/dev/null || true
  fi
  vm_wait_for_shutoff "${BUILDER}" "${SHUTOFF_WAIT_TRIES}" \
    || die "builder ${BUILDER} did not shut down; check: sudo virsh console ${BUILDER}"
  log "Builder is shut off."

  local i app vm ip launch_cmd
  for i in "${!APPS[@]}"; do
    app="${APPS[$i]}"
    vm="${APP_VMS[$i]}"
    confirm_delete_vm "$vm" ""
    log "Cloning ${BUILDER} -> ${vm}..."
    vm_clone "${BUILDER}" "${vm}" >> "${CLONE_LOG}" 2>&1
    if ! vm_enable_serial_log "${vm}" "$(serial_log_for "${vm}")" >> "${CLONE_LOG}" 2>&1; then
      log "WARNING: could not enable serial console logging for ${vm}"
    fi
    vm_start "${vm}"
    ip="$(vm_get_ip "${vm}")"
    vm_wait_for_ssh "${ip}" "${vm}"
    APP_VM_IP["$vm"]="$ip"
    record_state "APP_VM_IP_${vm}" "$ip"
    launch_cmd="$(build_launch_cmd "$app")"
    log "Launching build-remainder unit on ${vm} (${app}, ${IMAGE_TYPE})..."
    vm_ssh_to "${ip}" "${launch_cmd}" >> "$(remainder_log_for "${vm}")" 2>&1
  done
  record_state PHASE_appclone "$(date +%s)"
  log "All ${#APPS[@]} app VM(s) cloned and building in parallel."
}

# Watch every app VM run its remainder unit: status file over ssh while the
# offline firewall allows it, serial-log stage markers after, power-off as
# the success signal. One VM failing does not stop the others; failures are
# reported together at the end.
phase_finalize() {
  log "Watching ${#APP_VMS[@]} app VM(s) (offline + setup-machine + cleanup); success = VM powers itself off..."
  local vm
  for vm in "${APP_VMS[@]}"; do
    log "  ${vm}: serial log $(serial_log_for "${vm}")"
  done

  declare -A vm_done=() vm_failed=() last_status=() markers_seen=()
  local i j ip st total m markers slog
  for ((i = 0; i < FINALIZE_WAIT_TRIES; i++)); do
    local all_done=1
    for j in "${!APP_VMS[@]}"; do
      vm="${APP_VMS[$j]}"
      [[ -n "${vm_done[$vm]:-}" ]] && continue

      # Relay any new stage markers from this VM's serial log.
      slog="$(serial_log_for "${vm}")"
      total="$(sudo grep -ac 'VX-BUILD:' "${slog}" 2>/dev/null)" || total=0
      if ((total > ${markers_seen[$vm]:-0})); then
        mapfile -t markers < <(sudo grep -a 'VX-BUILD:' "${slog}" 2>/dev/null | tail -n "$((total - ${markers_seen[$vm]:-0}))")
        for m in "${markers[@]}"; do log "  [${vm}] ${m#*VX-BUILD: }"; done
        markers_seen[$vm]="$total"
      fi

      if ! vm_is_running "$vm"; then
        vm_done[$vm]=1
        log "  [${vm}] powered off — build complete."
        continue
      fi
      all_done=0

      # Status file polling works until this VM's offline firewall comes up.
      ip="${APP_VM_IP[$vm]:-}"
      if [[ -n "$ip" ]]; then
        if st="$(vm_ssh_to "$ip" "cat ${VM_FINALIZE_STATUS} 2>/dev/null || echo pending" 2>/dev/null)"; then
          if [[ "$st" != "${last_status[$vm]:-}" ]]; then
            log "  [${vm}] stage: ${st}"
            last_status[$vm]="$st"
          fi
          vm_ssh_to "$ip" "cat ${VM_FINALIZE_LOG} 2>/dev/null" > "$(remainder_log_for "${vm}")" 2>/dev/null || true
          case "$st" in
            offline-failed|setup-machine-failed|cleanup-failed|REFUSING*)
              vm_done[$vm]=1
              vm_failed[$vm]="$st"
              log "  [${vm}] FAILED: ${st} (VM left running for debugging)" ;;
          esac
        fi
      fi
    done
    ((all_done)) && break
    sleep 15
  done

  local failures=0 unfinished=0
  for vm in "${APP_VMS[@]}"; do
    [[ -n "${vm_failed[$vm]:-}" ]] && ((++failures))
    [[ -z "${vm_done[$vm]:-}" ]] && ((++unfinished)) \
      && log "  [${vm}] still running after $((FINALIZE_WAIT_TRIES * 15 / 60)) minutes"
  done
  ((unfinished == 0)) || die "some app VMs did not finish; inspect via sudo virsh console <vm>"
  ((failures == 0)) || die "${failures} app VM(s) failed; see stages above and debug via sudo virsh console <vm> (or the serial logs)"
  record_state PHASE_finalize "$(date +%s)"
  log "All app VM(s) built and powered off."
}

# lz4-compress each finished image and upload it to S3, following the manual
# process (image names prefixed with the date for bookkeeping). Only runs
# with --upload; requires the app VMs to be shut off.
phase_upload() {
  [[ "$UPLOAD" -eq 1 ]] || return 0
  local i app vm disk archive
  for i in "${!APPS[@]}"; do
    app="${APPS[$i]}"
    vm="${APP_VMS[$i]}"
    vm_is_running "$vm" \
      && die "refusing to compress running VM ${vm}; wait for finalize to power it off"
    disk="$(vm_disk_path "${vm}")"
    [[ -n "$disk" ]] || die "could not determine disk path for ${vm}"
    archive="${HOME}/$(date +%Y-%m-%d)-${IMAGE_NAME}-vx${app//-/}.img.lz4"
    [[ -e "$archive" ]] \
      && die "archive ${archive} already exists; remove it or rename the image"
    log "Compressing ${disk} -> ${archive}..."
    log "  log: ${UPLOAD_LOG}"
    sudo lz4 "${disk}" "${archive}" >> "${UPLOAD_LOG}" 2>&1 \
      || die "lz4 compression FAILED for ${vm}; see ${UPLOAD_LOG}"
    log "Uploading $(basename "${archive}") to ${S3_BUCKET}..."
    sudo aws s3 cp "${archive}" "${S3_BUCKET}" >> "${UPLOAD_LOG}" 2>&1 \
      || die "S3 upload FAILED for ${vm}; see ${UPLOAD_LOG}. The local archive is kept at ${archive}"
    log "Uploaded: ${S3_BUCKET}$(basename "${archive}")"
    record_state "UPLOADED_${vm}" "${S3_BUCKET}$(basename "${archive}")"
  done
  record_state PHASE_upload "$(date +%s)"
}

# --------------------------------------------------------------------- run
should_run base    && phase_base
should_run clone   && phase_clone
should_run start   && phase_start
case "$START_AT" in
  prep|online)
    # Resuming into a phase that needs a live ssh channel to the builder.
    vm_ensure_running "${BUILDER}" ;;
  appclone)
    vm_exists "${BUILDER}" || die "builder VM '${BUILDER}' does not exist" ;;
  finalize|upload)
    # Watch-only / compress-only; the app VMs just need to exist.
    for _vm in "${APP_VMS[@]}"; do
      vm_exists "$_vm" || die "app VM '$_vm' does not exist"
    done ;;
esac
should_run prep     && phase_prep
should_run online   && phase_online
should_run appclone && phase_appclone
should_run finalize && phase_finalize
[[ "$START_AT" == "upload" ]] && UPLOAD=1   # resuming into upload implies it
should_run upload   && phase_upload

log "========================================================="
if [[ "$UPLOAD" -eq 1 ]]; then
  log "DONE — image(s) built, compressed, and uploaded."
else
  log "DONE (compress/upload skipped; pass --upload to include them)."
fi
log ""
log "Built ${IMAGE_TYPE} image(s) for: ${APPS[*]}"
for _i in "${!APPS[@]}"; do
  log "  ${APP_VMS[$_i]}:  $(vm_disk_path "${APP_VMS[$_i]}")"
done
log "Builder VM '${BUILDER}' kept (shut off) for cloning more app types;"
log "remove it with: ./scripts/cleanup-vx-build.sh ${BUILDER}"
log ""
log "Build bootstrap has been removed from each app image:"
log "  - openssh-server purged"
log "  - ${VM_HOME}/.ssh removed"
log "  - ${VM_SUDOERS_FILE} removed"
log "  - config wizard will run on first boot (${VM_NEXT_BOOT_FLAG})"
log ""
log "  state:    ${STATE_FILE}"
log "  main log: ${MAIN_LOG}"
if [[ "$UPLOAD" -ne 1 ]]; then
  log ""
  log "To compress and upload later:  rerun with --start-at upload (same --app/--name)"
fi
