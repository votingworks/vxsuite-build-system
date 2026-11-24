#!/usr/bin/env bash
#
# Downloads the private DeskPro driver during the online phase, using AWS
# credentials from a vault-encrypted file on an attached disk image.

if [[ $EUID -eq 0 ]]; then
  echo "ERROR: This script should not be run via sudo."
  exit 1
fi

set -euo pipefail

ansible_inventory=${1:?usage: $0 <inventory> [ansible-playbook args...]}
shift
credentials_device=${DESKPRO_CREDENTIALS_DEVICE:-/dev/sda}
credentials_file=${DESKPRO_CREDENTIALS_FILE:-.aws.sh}

cd "$(dirname "${BASH_SOURCE[0]}")/.."

playbook=(ansible-playbook -i "inventories/${ansible_inventory}" playbooks/trusted_build/deskpro_driver.yaml --skip-tags offline "$@")

needs_credentials=$(ansible-inventory -i "inventories/${ansible_inventory}" --host localhost \
  | python3 -I -c 'import json, sys; d = json.load(sys.stdin).get("deskpro_driver") or {}; print(str(d.get("enabled") is True and "s3_region" in d).lower())')

if [[ "${needs_credentials}" != "true" ]]; then
  "${playbook[@]}"
  exit 0
fi

work_dir=$(mktemp -d)
mount_dir="${work_dir}/mnt"
mkdir "${mount_dir}"
cleanup() {
  sudo umount "${mount_dir}" 2>/dev/null || true
  rm -rf "${work_dir}"
}
trap cleanup EXIT

if ! sudo mount -o ro "${credentials_device}" "${mount_dir}" 2>/dev/null \
  && ! sudo mount -o ro "${credentials_device}1" "${mount_dir}" 2>/dev/null; then
  echo "ERROR: Could not mount ${credentials_device} with the AWS credentials for the DeskPro driver."
  exit 1
fi

sudo install -m 0600 -o "$(id -u)" "${mount_dir}/${credentials_file}" "${work_dir}/credentials"
sudo umount "${mount_dir}"

echo "Enter the vault password for ${credentials_file}."
credentials=$(ansible-vault view "${work_dir}/credentials")
rm -f "${work_dir}/credentials"
set -a
# shellcheck disable=SC1090
source <(printf '%s\n' "${credentials}")
set +a
unset credentials

"${playbook[@]}"
