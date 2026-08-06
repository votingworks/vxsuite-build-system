# shellcheck shell=bash
# build-image-args.sh — argument parsing, interactive prompts, and validation
# for build-vx-image.sh. Sourced, not executed; operates on the caller's
# globals and expects VALID_APPS, PHASES, REPO_DIR, and VM_KEY to be defined
# by the caller.
#
# Every question the pipeline will ever ask (including setup-machine's
# prompts) is collected up front here, before any phase runs. For QA images
# everything has a default; prod images additionally require a vx-vendor
# password and a release-image decision.

usage() {
  cat <<EOF
Usage: $(basename "${BASH_SOURCE[-1]}") [options]

Options (missing values are prompted for interactively; QA images have
defaults for everything):
  --inventory NAME              vxsuite-build-system inventory (default: latest)
  --complete-system-branch B    vxsuite-complete-system branch (default: main)
  --vxsuite-branch B            vxsuite branch override (default: none)
  --app APP[,APP...]            one or more (comma-separated) of:
                                ${VALID_APPS[*]}
  --type TYPE                   qa or prod (default: qa)
  --base-image NAME             base debian VM (from: sudo virsh list --all)
  --create-base-image           create a fresh base debian VM for the chosen
                                inventory first and build from it; mutually
                                exclusive with --base-image. Named by the
                                inventory's APT snapshot when it has one
                                (debian-v4.1.0-20260709-bookworm), otherwise
                                by creation date (debian-latest-<YYYYMMDD>-bookworm)
  --name NAME                   image name suffix; VM will be vx<app>-<name>
  --vendor-password PW          vx-vendor password (prod images only; QA
                                images always use "insecure")
  --release                     mark a prod image as an official release image
  --upload                      after the build, lz4-compress the image and
                                upload it to ${S3_BUCKET}
  --start-at PHASE              skip to a phase for an existing VM; one of:
                                ${PHASES[*]}
  --yes                         skip confirmation prompts (still errors rather
                                than deleting an existing VM)
  -h | --help                   show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --inventory)               INVENTORY="$2"; shift 2 ;;
      --complete-system-branch)  CS_BRANCH="$2"; shift 2 ;;
      --vxsuite-branch)          VX_BRANCH="$2"; shift 2 ;;
      --app)                     APP="$2"; shift 2 ;;
      --type)                    IMAGE_TYPE="$2"; shift 2 ;;
      --base-image)              BASE_IMAGE="$2"; shift 2 ;;
      --create-base-image)       CREATE_BASE=1; shift ;;
      --name)                    IMAGE_NAME="$2"; shift 2 ;;
      --vendor-password)         VENDOR_PASSWORD="$2"; shift 2 ;;
      --release)                 IS_RELEASE=1; shift ;;
      --upload)                  UPLOAD=1; shift ;;
      --start-at)                START_AT="$2"; shift 2 ;;
      --yes)                     ASSUME_YES=1; shift ;;
      -h|--help)                 usage; exit 0 ;;
      *)                         usage; die "unknown option: $1" ;;
    esac
  done
}

prompt_default() { # $1=prompt $2=default -> REPLY
  local answer
  read -rp "$1 [$2]: " answer
  REPLY="${answer:-$2}"
}

choose_from() { # $1=prompt, rest=options -> REPLY
  local prompt="$1"; shift
  local options=("$@") i answer
  echo "$prompt" >&2
  for i in "${!options[@]}"; do echo "  $((i + 1)). ${options[$i]}" >&2; done
  while true; do
    read -rp "Enter number (1-${#options[@]}): " answer
    if [[ "$answer" =~ ^[0-9]+$ ]] && ((answer >= 1 && answer <= ${#options[@]})); then
      REPLY="${options[$((answer - 1))]}"
      return
    fi
    echo "Invalid selection." >&2
  done
}

prompt_for_missing_args() {
  [[ -t 0 ]] || return 0
  prompt_default "vxsuite-build-system inventory" "${INVENTORY}"; INVENTORY="$REPLY"
  prompt_default "vxsuite-complete-system branch" "${CS_BRANCH}"; CS_BRANCH="$REPLY"
  if [[ -z "$VX_BRANCH" ]]; then
    read -rp "vxsuite branch override (empty for none): " VX_BRANCH
  fi
  if [[ -z "$APP" ]]; then
    echo "App(s) to build:" >&2
    local i
    for i in "${!VALID_APPS[@]}"; do echo "  $((i + 1)). ${VALID_APPS[$i]}" >&2; done
    local selection picks p
    read -rp "Enter comma-separated numbers: " selection
    IFS=',' read -ra picks <<< "$selection"
    for p in "${picks[@]}"; do
      p="${p// /}"
      [[ "$p" =~ ^[0-9]+$ ]] && ((p >= 1 && p <= ${#VALID_APPS[@]})) \
        || die "invalid selection: '$p'"
      APP+="${APP:+,}${VALID_APPS[$((p - 1))]}"
    done
  fi
  if [[ -z "$IMAGE_TYPE" ]]; then
    prompt_default "Image type (qa/prod)" "qa"; IMAGE_TYPE="$REPLY"
  fi
  # setup-machine's remaining questions, asked now so nothing prompts later.
  # QA images need neither: setup-machine defaults the vx-vendor password to
  # "insecure" and release only applies to prod.
  if [[ "$IMAGE_TYPE" == "prod" ]]; then
    if [[ "$IS_RELEASE" -eq 0 ]]; then
      read -rp "Is this an official release image? [y/N]: " release_answer
      [[ "$release_answer" =~ ^[Yy]$ ]] && IS_RELEASE=1
    fi
    while [[ -z "$VENDOR_PASSWORD" ]]; do
      local pw confirm
      read -rsp "Set vx-vendor password: " pw; echo
      read -rsp "Confirm vx-vendor password: " confirm; echo
      if [[ -n "$pw" && "$pw" == "$confirm" ]]; then
        VENDOR_PASSWORD="$pw"
      else
        echo "Passwords empty or do not match, try again." >&2
      fi
    done
  fi
  if [[ -z "$BASE_IMAGE" && "$CREATE_BASE" -ne 1 ]]; then
    local create_option="(create a fresh base image for inventory '${INVENTORY}')"
    local bases
    mapfile -t bases < <(sudo virsh list --all --name | grep '^debian' || true)
    choose_from "Base debian image:" "${bases[@]}" "$create_option"; BASE_IMAGE="$REPLY"
    if [[ "$BASE_IMAGE" == "$create_option" ]]; then
      CREATE_BASE=1
      BASE_IMAGE=""
    fi
  fi
  if [[ -z "$IMAGE_NAME" ]]; then
    read -rp "Image name (builder VM will be vx-<name>, app VMs vx<app>-<name>): " IMAGE_NAME
  fi
  if [[ "$UPLOAD" -ne 1 ]]; then
    local upload_answer
    read -rp "Compress and upload the finished image to ${S3_BUCKET}? [y/N]: " upload_answer
    [[ "$upload_answer" =~ ^[Yy]$ ]] && UPLOAD=1
  fi
}

validate_args() {
  # Split the (possibly comma-separated) app list into APPS, accepting
  # vxadmin/vxmark/etc. as aliases and dropping duplicates.
  APPS=()
  local _app _seen=","
  IFS=',' read -ra _raw_apps <<< "$APP"
  for _app in "${_raw_apps[@]}"; do
    _app="${_app// /}"
    _app="${_app#vx}"
    [[ -n "$_app" ]] || continue
    [[ " ${VALID_APPS[*]} " == *" ${_app} "* ]] \
      || die "app must be one or more of: ${VALID_APPS[*]} (got '${_app}')"
    [[ "$_seen" == *",${_app},"* ]] || { APPS+=("$_app"); _seen+="${_app},"; }
  done
  ((${#APPS[@]} > 0)) || die "at least one app is required"
  [[ -d "${REPO_DIR}/inventories/${INVENTORY}" ]] \
    || die "inventory '${INVENTORY}' not found in ${REPO_DIR}/inventories/"
  [[ "$IMAGE_TYPE" == "qa" || "$IMAGE_TYPE" == "prod" ]] \
    || die "type must be qa or prod (got '${IMAGE_TYPE:-<empty>}')"
  [[ -n "$IMAGE_NAME" ]] || die "image name is required"
  [[ "$IMAGE_NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]] \
    || die "image name must be lowercase alphanumeric/hyphens (got '${IMAGE_NAME}')"
  if [[ "$CREATE_BASE" -eq 1 ]]; then
    [[ -z "$BASE_IMAGE" ]] \
      || die "--base-image and --create-base-image are mutually exclusive"
    resolve_base_image_name
  else
    [[ -n "$BASE_IMAGE" ]] || die "base image is required (or pass --create-base-image)"
    sudo virsh dominfo "$BASE_IMAGE" >/dev/null 2>&1 \
      || die "base image VM '${BASE_IMAGE}' not found (see: sudo virsh list --all)"
  fi
  [[ -f "${VM_KEY}" && -f "${VM_KEY}.pub" ]] \
    || die "VM access key ${VM_KEY} not found; generate with: ssh-keygen -t ed25519 -f ${VM_KEY} -N ''"
  if [[ "$IMAGE_TYPE" == "prod" && -z "$VENDOR_PASSWORD" ]]; then
    die "prod images require --vendor-password (or run interactively)"
  fi
  if [[ "$IMAGE_TYPE" == "qa" ]]; then
    VENDOR_PASSWORD=""   # setup-machine defaults QA images to "insecure"
    IS_RELEASE=0
  fi
  if [[ -n "$START_AT" ]]; then
    [[ " ${PHASES[*]} " == *" ${START_AT} "* ]] \
      || die "--start-at must be one of: ${PHASES[*]} (got '${START_AT}')"
  fi
}
