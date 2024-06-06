To support reproducible builds for VVSG 2.0 certification requirements, we now host our own apt repos of all packages needed for a released build. To accomplish this, we use S3 (for hosting the repo), aptly (for creating and publishing the repo), and then configure our base image to only use this repo during the build process.

S3 is configured to host repos in a single bucket, using prefixes based on the date of the package snapshot we want to use for a release build. For example, a release created on June 7, 2024 will be found in the s3 bucket: s3://votingworks-apt-snapshots/20240607. Within this directory, the necessary apt repo structure+packages can be found, along with the public signing key required to verify the integrity of the repo. This S3 bucket can only be written to with AWS credentials limited to a unique user, granted access to this bucket, and protected with a passphrase only available to VotingWorks employees. 

To create and publish our apt repos, we use [aptly](https://www.aptly.info/). After completing the online phase of a Trusted Build, all necessary apt packages have been installed in the build VM. We then create an apt repo from this state. You can see the specific steps within: [create-aptly-release.sh](https://github.com/votingworks/vxsuite-build-system/blob/main/scripts/create-aptly-release.sh)

Of note: you will need to attach a virt .img file (accessible only to VotingWorks employees) to the VM used for the online phase which contains the GPG signing key used to sign the apt repo, along with the necessary S3 credentials to publish the repo. During the repo creation process, you will also be required to enter the passphrases associated with the GPG and S3 credentials. (If you would like to replicate this process in your own environment, you will need to expose your credentials to the VM as seen in then create-aptly-release.sh script. The specifics of that are left as an exercise to the reader.)

Once this .img file is available to the build VM, you can create a repo by running: `sudo ./scripts/create-aptly-release.sh` within the VM you performed (at a minimum) the online phase of Trusted Build.

Once the repo is successfully published, you can use it in future builds by configuring an Ansible inventory with two variables in the `packages.yaml` file: 
```
apt_snapshot_date: "20240607"
release_name: "bookworm"
```
Replace the `apt_snapshot_date` with the date you created the repo, and the appropriate Debian distribution release name. (We are currently using Debian 12, so the release should remain `bookworm` until otherwise noted.)
