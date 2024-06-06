#!/usr/bin/env bash
#
#-- Creating an aptly release involves several steps:
#-- Installing and configuring aptly
#-- Downloading all packages to the system
#-- Creating an aptly repo locally
#-- Taking a snapshot of that local repo
#-- Publishing the repo to S3
#-- Publishing the GPG public key
#-- 
#-- NOTE: This may be better as a playbook if we end up wanting to 
#--       use Ansible vault for aws credential management
#
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
source .virtualenv/ansible/bin/activate
ansible-vault decrypt /root/.aws.sh

apt list --installed | grep -v Listing | cut -d'/' -f1 > /var/tmp/packages.list

xargs apt-get install --reinstall --no-install-recommends --download-only -y < /var/tmp/packages.list

repo_date=$(date +%Y%m%d)

aptly repo create ${repo_date}

aptly repo add ${repo_date} /var/cache/apt/archives/

aptly snapshot create "${repo_date}-snapshot" from repo ${repo_date}

# source aws credentials
. /root/.aws.sh

# edit /root/.aptly.conf to have the S3PublishEndpoints block
# By default, empty S3 block will exist, so we just insert the required params
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

aws s3 cp /mnt/apt-votingworks.pub s3://votingworks-apt-snapshots/${repo_date}/votingworks-apt-${repo_date}.pub

umount /mnt

exit 0;
