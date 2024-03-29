#!/usr/bin/env bash

set -euo pipefail

vm_name=$1
vm_img_path="/var/lib/libvirt/images/${vm_name}.img"
vm_img_zip_path="${vm_img_path}.lz4"
vm_signed_image_file="${vm_name}-signed.img.lz4"
vm_vars_path="/var/lib/libvirt/qemu/nvram/${vm_name}_VARS.fd"
vm_xml_path="/tmp/${vm_name}-signed.xml"
hash_ref_path="/tmp/${vm_name}-signed-hashes.txt"
verify_hash_ref_path="/tmp/${vm_name}-verification-hashes.txt"
s3_path="s3://votingworks-trusted-build/signed"
s3_hash_ref_path="${s3_path}/${vm_name}-signed-hashes.txt"
s3_vars_path="${s3_path}/${vm_name}_VARS.fd"
s3_xml_path="${s3_path}/${vm_name}-signed.xml"
s3_img_zip_path="${s3_path}/${vm_name}.img.lz4"
s3_accelerate="https://s3-accelerate.amazonaws.com"

# Download all files from S3
echo ""
echo "Downloading signed files from ${s3_path}. This will take a few minutes."
aws s3 cp $s3_hash_ref_path $hash_ref_path
aws s3 cp $s3_vars_path $vm_vars_path
aws s3 cp $s3_xml_path $vm_xml_path
aws s3 cp $s3_img_zip_path $vm_img_zip_path --endpoint-url $s3_accelerate

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
echo "Calculating sha256 hashes of all signed files to verify against."
sha256sum $vm_img_zip_path >> $verify_hash_ref_path
sha256sum $vm_vars_path >> $verify_hash_ref_path
sha256sum $vm_xml_path >> $verify_hash_ref_path

echo ""
echo "Comparing hashes of all signed files."
if ! diff $hash_ref_path $verify_hash_ref_path >/dev/null 2>&1
then
  echo "ERROR: Hashes do not match."
  exit 1
else
  echo "Successfully verified all signed files hashes are correct."
fi

mv $vm_img_zip_path ~/$vm_signed_image_file

echo ""
echo "The signed download process is now complete."
echo ""

exit 0;
