export DEBCONF_FRONTEND=noninteractive
export DEBIAN_FRONTEND=noninteractive
export TERM=xterm
echo "#####################################################"
echo `whoami`
echo "#####################################################"
echo 'packer' | sudo -S apt update
echo 'packer' | sudo -S apt install -y sudo vim git make build-essential lsb-release cups rsync cryptsetup efitools gpg gpg-agent
mkdir -p /home/packer/code/votingworks
cd /home/packer/code/votingworks
git clone https://github.com/votingworks/vxsuite-complete-system
cd vxsuite-complete-system
echo 'packer' | sudo -S make deps
make checkout
echo 'packer' | sudo -S make build

