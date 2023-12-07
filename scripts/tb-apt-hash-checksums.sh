#!/usr/bin/env bash

set -euo pipefail

#-- Directory where packages are found
package_dir=/var/cache/apt/archives

#-- Reference file storing md5sum sha56sum package_name
checksum_output=/tmp/apt_package_checksum_reference.txt

#-- Delete the output file if already exists
if [[ -f $checksum_output ]]; then
  rm $checksum_output
fi

cd $package_dir

#-- Loop over all *.deb packages and generate md5sum and sha256sum
for pkg in `ls -1 *.deb`
do
  md5=""
  sha256sum=""
  md5=`md5sum $pkg | cut -d' ' -f1`
  sha256=`sha256sum $pkg | cut -d' ' -f1`
  echo "$md5 $sha256 $pkg" >> $checksum_output
done

echo "You can find the expected checksums in: $checksum_output"

exit 0
