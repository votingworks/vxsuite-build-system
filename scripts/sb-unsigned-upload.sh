#!/usr/bin/env bash

set -euo pipefail

vm_name=$1
vm_img_path="/var/lib/libvirt/images/${vm_name}.img"
vm_img_zip_path="${vm_img_path}.lz4"
vm_vars_path="/var/lib/libvirt/qemu/nvram/${vm_name}_VARS.fd"
vm_xml_path="/tmp/${vm_name}-unsigned.xml"
hash_ref_path="/tmp/${vm_name}-unsigned-hashes.txt"
s3_path="s3://votingworks-trusted-build/unsigned/"
s3_accelerate="https://s3-accelerate.amazonaws.com"

# Verify the image exists
if [[ ! -f $vm_img_path ]]; then
  echo "ERROR: The $vm_name img ($vm_img_path) could not be found."
  exit 1
fi
#
# Export the image's XML configuration
virsh dumpxml $vm_name > $vm_xml_path

# Compress the img w/ lz4
echo ""
echo "Compressing ${vm_img_path}. This may take a few minutes."
lz4 $vm_img_path

# If the hash ref file is present, delete it
# and create a new, empty file
if [[ -f $hash_ref_path ]]; then
  rm $hash_ref_path
  touch $hash_ref_path
fi

# Generate sha256 hashes of all files
echo ""
echo "Calculating sha256 hashes of all unsigned files."
sha256sum $vm_img_zip_path >> $hash_ref_path
sha256sum $vm_vars_path >> $hash_ref_path
sha256sum $vm_xml_path >> $hash_ref_path

# Upload all files to S3
echo ""
echo "Uploading unsigned files to ${s3_path}. This will take a few minutes."
aws s3 cp $hash_ref_path $s3_path
aws s3 cp $vm_vars_path $s3_path
aws s3 cp $vm_xml_path $s3_path
aws s3 cp $vm_img_zip_path $s3_path --endpoint-url $s3_accelerate

echo ""
echo "The unsigned upload process is now complete."
echo ""

exit 0;
