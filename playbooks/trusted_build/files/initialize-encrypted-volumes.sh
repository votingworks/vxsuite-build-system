#!/bin/bash

set -euo pipefail

# TODO: add error checking
# TODO?: support passing multiple partitions
encrypted_dev_path='/dev/Vx-vg/var_encrypted'
decrypted_map_name='var_decrypted'
decrypted_dev_path="/dev/mapper/${decrypted_map_name}"
insecure_key='/home/insecure.key'
tmp_mnt_path='/mnt/tmp_dir'
partition_path='/var'

if [ ! -e "${encrypted_dev_path}" ]; then
  echo "There is no encrypted partition defined in LVM."
  echo "The build process will continue, assuming no encryption."
  exit 0
fi

if [ -e "${decrypted_dev_path}" ]; then
  echo "Encryption appears to already be configured. No initialization is needed."
  exit 0
fi

# Using an empty passphrase during initial encryption 
# This will allow use of the try-empty-passsword option on first boot
# After that, the TPM will be the only valid method for decrypting the drive
echo -n "" > ${insecure_key}

echo "Preparing ${encrypted_dev_path} for encryption..."
cryptsetup luksFormat -q --cipher aes-xts-plain64 --key-size 512 --hash sha256 --key-file ${insecure_key} ${encrypted_dev_path}

echo "Mapping ${encrypted_dev_path} to ${decrypted_map_name}..."
cryptsetup open --type luks --key-file ${insecure_key} ${encrypted_dev_path} ${decrypted_map_name}

echo "Putting ext4 filesystem on ${decrypted_dev_path}"
mkfs.ext4 ${decrypted_dev_path}

mkdir -p ${tmp_mnt_path}
mount ${decrypted_dev_path} ${tmp_mnt_path}
echo "Copying ${partition_path} to ${decrypted_dev_path}..."
rsync -a "${partition_path}/" "${tmp_mnt_path}/"

echo "Cleaning up various copy related operations..."
umount ${tmp_mnt_path}
rm -rf ${tmp_mnt_path}
rm -rf ${partition_path}
mkdir ${partition_path}
mount ${decrypted_dev_path} ${partition_path}

echo "Updating /etc/crypttab and /etc/fstab..."
echo "${decrypted_map_name} ${encrypted_dev_path} ${insecure_key} try-empty-password,luks" >> /etc/crypttab
echo "${decrypted_dev_path} ${partition_path} ext4 defaults 0 2" >> /etc/fstab 

echo "${partition_path} encryption has been initialized."

exit 0;
