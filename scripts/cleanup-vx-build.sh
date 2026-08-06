#!/usr/bin/env bash

# cleanup-vx-build.sh — remove build VMs and the logs from their runs.
#
# Runs on the build server. With no arguments, lists all libvirt VMs
# (sudo virsh list --all) and asks which to clean up (comma-separated
# numbers). VM names can also be passed directly as arguments (comma- or
# space-separated). For every selected VM this removes:
#   - the VM itself (destroyed if running, undefined with its NVRAM)
#   - its disk image(s)
#   - its run logs:  ~/build-logs/<vm>-*.log*  and  ~/build-logs/<vm>.state
#   - its serial console log:  /var/log/libvirt/qemu/<vm>-serial.log
# A VM name whose domain is already gone is still accepted, cleaning up
# leftover logs only. Compressed image archives (~/​*.img.lz4) are never
# touched — those are deliverables.

set -euo pipefail
shopt -s nullglob

LOG_DIR="${HOME}/build-logs"
SERIAL_LOG_DIR="/var/log/libvirt/qemu"

log() { echo "[$(date +%H:%M:%S)] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [--yes] [vm-name[,vm-name...] ...]

With no VM names, presents an interactive menu of all VMs.
  --yes    skip the final confirmation (VM names must be given as arguments)
EOF
}

ASSUME_YES=0
TARGETS=()
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --yes)     ASSUME_YES=1 ;;
    -*)        usage; die "unknown option: $arg" ;;
    *)         IFS=',' read -ra parts <<< "$arg"
               for p in "${parts[@]}"; do [[ -n "$p" ]] && TARGETS+=("$p"); done ;;
  esac
done

vm_exists() { sudo virsh dominfo "$1" >/dev/null 2>&1; }

run_logs_for() { # $1=name -> prints matching log/state files, one per line
  local name="$1" f
  for f in "${LOG_DIR}/${name}-"*.log* "${LOG_DIR}/${name}.state"; do
    [[ -e "$f" ]] && echo "$f"
  done
  [[ -e "${SERIAL_LOG_DIR}/${name}-serial.log" ]] \
    && echo "${SERIAL_LOG_DIR}/${name}-serial.log"
  return 0
}

# ------------------------------------------------------------ interactive menu
if ((${#TARGETS[@]} == 0)); then
  [[ -t 0 ]] || die "no VM names given and not running interactively"
  mapfile -t all_vms < <(sudo virsh list --all --name | sed '/^$/d')
  ((${#all_vms[@]} > 0)) || die "no VMs found"
  echo "VMs on this host:"
  for i in "${!all_vms[@]}"; do
    state="$(sudo virsh domstate "${all_vms[$i]}" 2>/dev/null || echo '?')"
    nlogs="$(run_logs_for "${all_vms[$i]}" | wc -l)"
    printf '  %2d. %-45s %-10s %s\n' "$((i + 1))" "${all_vms[$i]}" "($state)" \
      "$([[ "$nlogs" -gt 0 ]] && echo "[$nlogs log file(s)]")"
  done
  read -rp "VMs to clean up (comma-separated numbers, empty to abort): " selection
  [[ -n "$selection" ]] || die "nothing selected"
  IFS=',' read -ra picks <<< "$selection"
  for p in "${picks[@]}"; do
    p="${p// /}"
    [[ "$p" =~ ^[0-9]+$ ]] && ((p >= 1 && p <= ${#all_vms[@]})) \
      || die "invalid selection: '$p'"
    TARGETS+=("${all_vms[$((p - 1))]}")
  done
fi

# --------------------------------------------------------------- build the plan
declare -A PLAN_DISKS PLAN_LOGS PLAN_STATE
for name in "${TARGETS[@]}"; do
  if vm_exists "$name"; then
    PLAN_STATE[$name]="$(sudo virsh domstate "$name" 2>/dev/null || echo '?')"
    PLAN_DISKS[$name]="$(sudo virsh domblklist "$name" --details 2>/dev/null \
      | awk '$2 == "disk" {print $4}')"
  else
    PLAN_STATE[$name]="(no such VM — logs only)"
    PLAN_DISKS[$name]=""
  fi
  PLAN_LOGS[$name]="$(run_logs_for "$name")"
  if [[ "${PLAN_STATE[$name]}" == "(no such VM — logs only)" && -z "${PLAN_LOGS[$name]}" ]]; then
    die "'$name' is neither a VM nor has any logs in ${LOG_DIR}"
  fi
done

echo
echo "Will remove:"
for name in "${TARGETS[@]}"; do
  echo "  ${name}  ${PLAN_STATE[$name]}"
  while IFS= read -r d; do [[ -n "$d" ]] && echo "    disk: $d"; done <<< "${PLAN_DISKS[$name]}"
  while IFS= read -r f; do [[ -n "$f" ]] && echo "    log:  $f"; done <<< "${PLAN_LOGS[$name]}"
done
echo

if [[ "$ASSUME_YES" -ne 1 ]]; then
  [[ -t 0 ]] || die "refusing to delete without confirmation (pass --yes with explicit VM names)"
  read -rp "Proceed? [y/N]: " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || die "aborted; nothing removed"
fi

# --------------------------------------------------------------------- execute
for name in "${TARGETS[@]}"; do
  if vm_exists "$name"; then
    sudo virsh destroy "$name" >/dev/null 2>&1 || true
    sudo virsh undefine --nvram "$name" >/dev/null
    log "removed VM ${name}"
    while IFS= read -r d; do
      [[ -n "$d" && -f "$d" ]] && sudo rm -f "$d" && log "removed disk $d"
    done <<< "${PLAN_DISKS[$name]}"
  fi
  while IFS= read -r f; do
    [[ -n "$f" ]] && sudo rm -f "$f" && log "removed log $f"
  done <<< "${PLAN_LOGS[$name]}"
done
log "Done."
