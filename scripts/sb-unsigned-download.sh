#!/usr/bin/env bash

set -euo pipefail

vm_name=$1
vm_img_path="/var/lib/libvirt/images/${vm_name}.img"
vm_img_zip_path="${vm_img_path}.lz4"
vm_vars_path="/var/lib/libvirt/qemu/nvram/${vm_name}_VARS.fd"
vm_xml_path="/tmp/${vm_name}-unsigned.xml"
hash_ref_path="/tmp/${vm_name}-unsigned-hashes.txt"
verify_hash_ref_path="/tmp/${vm_name}-verification-hashes.txt"
s3_path="s3://votingworks-trusted-build/unsigned"
s3_hash_ref_path="${s3_path}/${vm_name}-unsigned-hashes.txt"
s3_vars_path="${s3_path}/${vm_name}_VARS.fd"
s3_xml_path="${s3_path}/${vm_name}-unsigned.xml"
s3_img_zip_path="${s3_path}/${vm_name}.img.lz4"

# Download all files from S3
echo ""
echo "Downloading unsigned files from ${s3_path}. This will take a few minutes."
aws s3 cp $s3_hash_ref_path $hash_ref_path
aws s3 cp $s3_vars_path $vm_vars_path
aws s3 cp $s3_xml_path $vm_xml_path
aws s3 cp $s3_img_zip_path $vm_img_zip_path

# Verify the image exists
if [[ ! -f $vm_img_zip_path ]]; then
  echo "ERROR: The compressed $vm_name img ($vm_img_zip_path) could not be found."
  exit 1
fi

# If the verification hash ref file is present, delete it
# and create a new, empty file
if [[ -f $verify_hash_ref_path ]]; then
  rm $verify_hash_ref_path
  touch $verify_hash_ref_path
fi

# Generate sha256 hashes of all files
echo ""
echo "Calculating sha256 hashes of all unsigned files to verify against."
sha256sum $vm_img_zip_path >> $verify_hash_ref_path
sha256sum $vm_vars_path >> $verify_hash_ref_path
sha256sum $vm_xml_path >> $verify_hash_ref_path

echo ""
echo "Comparing hashes of all unsigned files."
if ! diff $hash_ref_path $verify_hash_ref_path >/dev/null 2>&1
then
  echo "ERROR: Hashes do not match."
  exit 1
else
  echo "Successfully verified all unsigned files hashes are correct."
fi

# Decompress the img w/ lz4
echo ""
echo "Decompressing ${vm_img_zip_path}. This may take a few minutes."
lz4 $vm_img_zip_path

# Create the image from the XML configuration
echo "Define the $vm_name configuration."
virsh define $vm_xml_path

echo ""
echo "The unsigned download process is now complete."
echo ""

exit 0;
