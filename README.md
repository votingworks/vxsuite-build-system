# vxsuite-build-system

# Prerequisites

1. Parallels for Mac
2. Parallels Virtualization SDK for Mac: https://www.parallels.com/products/desktop/download/
3. After both of these are installed, run: `sudo ln -s /Library/Frameworks/Python.framework/Versions/3.7/lib/python3.7/site-packages/prlsdkapi.pth /Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/lib/python3.9/site-packages/prlsdkapi.pth`
4. Install `packer` via homebrew:
    1. `brew tap hashicorp/tap`
    2. `brew install hashicorp/tap/packer`
    3. (Optional, but recommend: `brew upgrade hashicorp/tap/packer`

# Build a base vxsuite VM with no shared path from your Mac

1. Run: `packer build parallels-debian11.pkr.hcl` (This will take 7-15 minutes, depending on your machine)
2. Once it completes, run: `open builds/packer-debian-11.6-arm64-parallels/debian-11.6-arm64.pvm/`
3. For now, credentials are: `packer / packer`
