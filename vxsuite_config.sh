export DEBCONF_FRONTEND=noninteractive
export DEBIAN_FRONTEND=noninteractive
export TERM=xterm
echo "#####################################################"
echo `whoami`
echo "#####################################################"
sudo apt update
sudo apt install -y git make
mkdir -p /home/packer/code/
cd /home/packer/code/
git clone https://github.com/votingworks/vxsuite
cd vxsuite
./script/setup-dev
./script/bootstrap

