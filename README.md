# vxsuite-build-system

vxsuite-build-system is our framework for building VxSuite and managing its dependencies, across versions and environments.

## Prerequisites

1. Parallels Pro for Mac: https://www.parallels.com/products/desktop/pro/
2. Parallels Virtualization SDK for Mac: https://www.parallels.com/products/desktop/download/
3. Xcode Command Line Tools (There are multiple ways to install this. A simple method: `xcode-select --install`
4. Install `packer` via homebrew (if you don't already have homebrew installed, you can install homebrew via instructions here: https://brew.sh/):
   1. `brew tap hashicorp/tap`
   2. `brew install hashicorp/tap/packer`
   3. (Optional, but recommended): `brew upgrade hashicorp/tap/packer`

## Clone and initialize the vxsuite-build-system repository

1. Clone vxsuite-build-system via https or ssh
   1. Via https: `git clone https://github.com/votingworks/vxsuite-build-system.git`
   2. Via ssh: `git clone git@github.com:votingworks/vxsuite-build-system.git`
2. Initialize packer
   1. Be sure to `cd` into the newly cloned vxsuite-build-system repo
   2. Run: `packer init parallels-debian12.pkr.hcl`

## Build a base Debian VM with VotingWorks repositories cloned

1. Run: `packer build parallels-debian12.pkr.hcl` (This will take 10-20 minutes, depending on your machine and internet speed. You can watch the progress by opening the VM from the Parallels Control Center.)
2. Once it completes, you will have a new VM available in your local Parallels directory. This is `~/Parallels` by default. To start this VM, run: `open ~/Parallels/debian-11.6-arm64.pvm/`
3. The default username is `vx` with a default password of `changeme`

## Additional options

You can further customize your Parallels VM with various options provided to the `packer build` command. Unless otherwise noted, you can combine as many of these in a single command as you want.

### Use a custom user account

If you'd like to change the default username, use the `local_user` variable.

For example: `packer build -var "local_user=your_username" parallels-debian12.pkr.hcl`

### Share a folder from your Mac to the Parallels VM

It's possible to make a local folder accessible to this Parallels VM via two variables.

- `shared_path` - the full path on your local machine to make available in the VM (default is /tmp)
- `enable_shared_path` - whether to enable/disable sharing. The default is `disable`

For example, to share your home directory to the VM:
`packer build -var "shared_path=/Users/your_username" -var "enable_shared_path=enable" parallels-debian12.pkr.hcl`

### Define CPU and Memory (RAM) resources allocated to the VM:

Depending on your needs, you can increase or decrease the resources allocated to your VM.

- `vm_cpus` - This determines how many CPUs are available to the VM. The default is 2.
- `vm_memory` - This determines the amount of RAM (in megabytes) available to the VM. The default is 8192 (8GB).

For example, to allocate 4 CPUs and 16 GB of RAM to a VM:
`packer build -var "vm_cpus=4" -var "vm_memory=16384" parallels-debian12.pkr.hcl`

### Rename your VM

To change the name of the VM being built, use the `vm_name` variable (default is debian-11.6-arm64.pvm)

For example, to name your VM "MyVM":
`packer build -var "vm_name=MyVM" parallels-debian12.pkr.hcl`

## License

All files are licensed under GNU GPL v3.0 only. Refer to the [license file](./LICENSE) for
more information.
