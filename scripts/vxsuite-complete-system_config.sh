export DEBCONF_FRONTEND=noninteractive
export DEBIAN_FRONTEND=noninteractive
export TERM=xterm
sudo -S apt update
sudo -S apt install -y sudo vim git make build-essential lsb-release cups rsync cryptsetup efitools gpg gpg-agent
mkdir -p /home/packer/code/votingworks
cd /home/packer/code/votingworks
git clone https://github.com/votingworks/vxsuite-complete-system
cd vxsuite-complete-system
git checkout $1
make deps
make checkout
make build

