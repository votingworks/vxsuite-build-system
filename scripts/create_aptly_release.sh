#!/usr/bin/env bash
#
#-- Creating an aptly release involves several steps:
#-- Installing and configuring aptly
#-- Creating a GPG key for signing the repo
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

apt install -y aptly awscli

gpg --batch --passphrase '' --quick-gen-key apt@voting.works

gpg --armor --export apt@voting.works > /var/tmp/apt-votingworks.pub

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


aptly -distribution="bookworm" publish snapshot "${repo_date}-snapshot" s3:votingworks-apt-snapshots:${repo_date}/

aws s3 cp /var/tmp/apt-votingworks.pub s3://votingworks-apt-snapshots:${repo_date}/votingworks-apt-${repo_date}.pub
