#!/usr/bin/env bash
#
# Note: This script assumes a virt .img file mounted to the VM at /dev/sda
#       for access to secure credentials. 

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run this script as root via: sudo ./scripts/create-aptly-release.sh"
  exit 1;
fi

apt install -y aptly awscli

umount /dev/sda || true
umount /dev/sda1 || true
mount /dev/sda /mnt || mount /dev/sda1 /mnt || (echo "GPG and AWS credentials were not found, exiting" && sleep 5 && exit);

gpg --import /mnt/apt-votingworks.asc
cp /mnt/.aws.sh /root/.aws.sh

# Assumes ansible is already available due to being run in a build VM
# We could eliminate this assumption and run the Ansible install script
# but I'm ok with this assumption for now.
source .virtualenv/ansible/bin/activate
ansible-vault decrypt /root/.aws.sh

# Export the list of packages we need to verify are part of the repo we'll be publishing
apt list --installed | grep -v Listing | cut -d'/' -f1 > /var/tmp/packages.list

# Download (as necessary) to the apt cache archive
xargs apt-get install --reinstall --no-install-recommends --download-only -y < /var/tmp/packages.list

repo_date=$(date +%Y%m%d)

aptly repo create ${repo_date}

aptly repo add ${repo_date} /var/cache/apt/archives/

# We only create a snapshot because it makes S3 publishing a bit easier
aptly snapshot create "${repo_date}-snapshot" from repo ${repo_date}

# source aws credentials
. /root/.aws.sh

# edit /root/.aptly.conf to have the S3PublishEndpoints block
# By default, an empty S3 block will exist, so we just insert the required params
sed -i -e 's/.*"S3PublishEndpoints".*/  "S3PublishEndpoints": {\
     "votingworks-apt-snapshots":{\
        "region":"us-west-2",\
        "bucket":"votingworks-apt-snapshots",\
        "prefix":"'${repo_date}'",\
        "acl":"none"\
     }\
   },/' /root/.aptly.conf


# This command can fail intermittently depending on size of the repo
# and/or the available network connection. As a result, we retry a few times.
set +e
(
  i=1
  while [ $i -le 3 ]
  do
    aptly -distribution="bookworm" publish snapshot "${repo_date}-snapshot" s3:votingworks-apt-snapshots:${repo_date}/
    if [[ "$?" == "0" ]]; then
      break
    else
      i=$(( $i + 1 ))
    fi
  done
  if [[ $i -gt 3 ]]; then
    exit 1;
  fi
)
set -e

# publish the public key so any system building from this repo can verify the integrity of the release
aws s3 cp /mnt/apt-votingworks.pub s3://votingworks-apt-snapshots/${repo_date}/votingworks-apt-${repo_date}.pub

umount /mnt

exit 0;
