# vxsuite-build-system

# Prerequisites

1. Parallels Pro for Mac: https://www.parallels.com/products/desktop/pro/
2. Parallels Virtualization SDK for Mac: https://www.parallels.com/products/desktop/download/
3. Xcode Command Line Tools (They are multiple ways to install this. A simple method: `xcode-select --install`
4. After these are installed, run: `sudo ln -s /Library/Frameworks/Python.framework/Versions/3.7/lib/python3.7/site-packages/prlsdkapi.pth /Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/lib/python3.9/site-packages/prlsdkapi.pth`
    1. NOTE: This is due to a known issue in Parallels and may not be necessary in the future. 
5. Install `packer` via homebrew (if you don't already have homebrew installed, you can install homebrew via instructions here: https://brew.sh/):
    1. `brew tap hashicorp/tap`
    2. `brew install hashicorp/tap/packer`
    3. (Optional, but recommended): `brew upgrade hashicorp/tap/packer`

# Clone and initialize the `vxsuite-build-system` repository

1. Clone `vxsuite-build-system` via https or ssh
    1. Via https: `git clone https://github.com/votingworks/vxsuite-build-system.git`
    2. Via ssh: `git clone git@github.com:votingworks/vxsuite-build-system.git`
2. Initialize packer
    1. Be sure to cd into the newly cloned `vxsuite-build-system` repo
    2. Run: `packer init .`

# Build a base Debian VM with VotingWorks repositories cloned

1. Run: `packer build parallels-debian11.pkr.hcl` (This will take 10-20 minutes, depending on your machine)
2. Once it completes, you will have a new VM available in your local Parallels directory. This is `~/Parallels` by default. To start this VM, run: `open ~/Parallels/debian-11.6-arm64.pvm/`
3. The default username is `vx` with a default password of `changeme`
