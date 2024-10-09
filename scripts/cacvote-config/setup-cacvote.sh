#!/bin/bash

# /vx/ui --> home directory for the vx-ui user (rw with symlink for ro files)
# /vx/services --> home directory for the vx-services user (rw with symlink for ro files)
# /vx/admin --> home directory for the vx-admin user (rw with symlink for ro files)
# /vx/code --> all the executable code (ro)
# /vx/data --> all the scans and sqlite database for services
# /vx/config --> machine configuration that spans all the users.

set -euo pipefail

export PATH=${PATH}:/sbin/

# which kind of machine are we setting up?
echo "Welcome to CACVote. THIS IS A DESTRUCTIVE SCRIPT. Ctrl-C right now if you don't know for sure what you're doing."
echo "Which machine are we building today?"

CHOICES=('')
MODEL_NAMES=('')

echo
echo "${#CHOICES[@]}. CACVote Admin"
CHOICES+=('cacvote-jx-terminal')
MODEL_NAMES+=('cacvote-jx-terminal')

echo "${#CHOICES[@]}. CACVote Mark"
CHOICES+=('cacvote-mark')
MODEL_NAMES+=('cacvote-mark')

echo
read -p "Select machine: " CHOICE_INDEX

if [ "${CHOICE_INDEX}" -ge "${#CHOICES[@]}" ] || [ "${CHOICE_INDEX}" -lt 1 ]
then
    echo "You need to select a valid machine type."
    exit 1
fi

CHOICE=${CHOICES[$CHOICE_INDEX]}
MODEL_NAME=${MODEL_NAMES[$CHOICE_INDEX]}

echo "Excellent, let's set up ${CHOICE}."

echo
read -p "Is this image for QA where you want sudo privileges, the ability to record screengrabs, etc.? [y/N] " qa_image_flag

if [[ $qa_image_flag == 'y' || $qa_image_flag == 'Y' ]]; then
    VXADMIN_SUDO=1
    ADMIN_PASSWORD='insecure'
    echo "OK, creating a QA image with vx-admin sudo privileges."
    echo "Using password insecure for vx-admin user."
else
    VXADMIN_SUDO=0
    echo "Ok, creating a production image. No sudo privileges for anyone!"
    echo
    echo "Next, we need to set the admin password for this machine."
    while true; do
        read -s -p "Set vx-admin password: " ADMIN_PASSWORD
        echo
        read -s -p "Confirm vx-admin password: " CONFIRM_PASSWORD
        echo
        if [[ "${ADMIN_PASSWORD}" = "${CONFIRM_PASSWORD}" ]]
        then
            echo "Password confirmed."
            break
        else
            echo "Passwords do not match, try again."
        fi
    done
fi

echo
echo "The script will take it from here and set up the machine."
echo

sudo chown :lpadmin /sbin/lpinfo
echo "export PATH=$PATH:/sbin" | sudo tee -a /etc/bash.bashrc

# turn off automatic updates
sudo cp config/20auto-upgrades /etc/apt/apt.conf.d/

# make sure machine never shuts down on idle, and does shut down on power key (no hibernate or anything.)
sudo cp config/logind.conf /etc/systemd/

echo "Creating necessary directories"
# directory structure
sudo mkdir -p /vx/code
sudo mkdir -p /var/vx
sudo mkdir -p /var/vx/ui
sudo mkdir -p /var/vx/data
sudo mkdir -p /var/vx/admin
sudo mkdir -p /var/vx/services

sudo ln -sf /var/vx/data /vx/data

# mutable homedirs because we haven't figured out how to do this well yet.
sudo ln -sf /var/vx/ui /vx/ui
sudo ln -sf /var/vx/admin /vx/admin
sudo ln -sf /var/vx/services /vx/services

echo "Creating users"
# create users, no common group, specified uids.
id -u vx-ui &> /dev/null || sudo useradd -u 1751 -m -d /var/vx/ui -s /bin/bash vx-ui
id -u vx-admin &> /dev/null || sudo useradd -u 1752 -m -d /var/vx/admin -s /bin/bash vx-admin
id -u vx-services &> /dev/null || sudo useradd -u 1750 -m -d /var/vx/services vx-services

# a vx group for all vx users
getent group vx-group || sudo groupadd -g 800 vx-group
sudo usermod -aG vx-group vx-ui
sudo usermod -aG vx-group vx-admin
sudo usermod -aG vx-group vx-services

# ensure `vx-services` can use the TPM
sudo usermod -aG tss vx-services

sudo usermod -aG video vx-ui

# remove all files created by default
sudo rm -rf /vx/services/* /vx/ui/* /vx/admin/*

# Let all of our users read logs
sudo usermod -aG adm vx-ui
sudo usermod -aG adm vx-admin
sudo usermod -aG adm vx-services

# Set up log config
sudo bash setup-scripts/setup-logging.sh

# set up mount point ahead of time because read-only later
sudo mkdir -p /media/vx/usb-drive
sudo chown -R vx-ui:vx-group /media/vx

# let vx-services manage printers
sudo usermod -aG lpadmin vx-services

### set up CUPS to read/write all config out of /var to be compatible with read-only root filesystem

# copy existing cups config structure to new /var location
#sudo mkdir /var/etc
#sudo cp -rp /etc/cups /var/etc/
#sudo rm -rf /etc/cups

# set up cups config files that internally include appropriate paths with /var
#sudo cp config/cupsd.conf /var/etc/cups/
#sudo cp config/cups-files.conf /var/etc/cups/

# modify cups systemd service to read config files from /var
#sudo cp config/cups.service /usr/lib/systemd/system/

# modified apparmor profiles to allow cups to access config files in /var
#sudo cp config/apparmor.d/usr.sbin.cupsd /etc/apparmor.d/
#sudo cp config/apparmor.d/usr.sbin.cups-browsed /etc/apparmor.d/

echo "Setting up the code"
cacvote_dir=/home/vx/code/cacvote
sudo cp -rp ${cacvote_dir}/build/cacvote /vx/code/
sudo cp -rp config /vx/code/
sudo cp -rp app-scripts /vx/code/
sudo cp run-scripts/run-${CHOICE}.sh /vx/code/
sudo cp run-scripts/run-kiosk-browser.sh /vx/code/
sudo cp run-scripts/run-kiosk-browser-forever-and-log.sh /vx/code/
sudo ln -s /vx/code/cacvote/libs/auth/certs /vx/code/cacvote/libs/auth/src/certs

echo "Copying ElectionGuard"
eg_dir=/home/vx/code/egk-ec-mix-net
sudo cp -rp ${eg_dir} /vx/code/

# symlink the code and run-*.sh in /vx/services
sudo ln -s /vx/code/cacvote /vx/services/cacvote
sudo ln -s /vx/code/run-${CHOICE}.sh /vx/services/run-${CHOICE}.sh

# symlink appropriate vx/ui files
sudo ln -s /vx/code/config/ui_bash_profile /vx/ui/.bash_profile
sudo ln -s /vx/code/config/Xresources /vx/ui/.Xresources
sudo ln -s /vx/code/config/xinitrc /vx/ui/.xinitrc
sudo ln -s /vx/code/config/chime.wav /vx/ui/chime.wav

# symlink the GTK .settings.ini
sudo mkdir -p /vx/ui/.config/gtk-3.0
sudo ln -s /vx/code/config/gtksettings.ini /vx/ui/.config/gtk-3.0/settings.ini

# Hooks for dm-verity
sudo cp config/dmverity-root.hook /etc/initramfs-tools/hooks/dmverity-root
sudo cp config/dmverity-root.script /etc/initramfs-tools/scripts/local-premount/dmverity-root

# admin function scripts
sudo ln -s /vx/code/config/admin_bash_profile /vx/admin/.bash_profile
sudo ln -s /vx/code/config/admin-functions /vx/admin/admin-functions

# Make sure our cmdline file is readable by vx-admin
sudo mkdir -p /vx/admin/config
sudo cp config/cmdline /vx/code/config/cmdline
sudo cp config/logo.bmp /vx/code/config/logo.bmp
sudo cp config/grub.cfg /vx/code/config/grub.cfg
sudo ln -s /vx/code/config/cmdline /vx/admin/config/cmdline
sudo ln -s /vx/code/config/logo.bmp /vx/admin/config/logo.bmp
sudo ln -s /vx/code/config/grub.cfg /vx/admin/config/grub.cfg

# machine configuration
sudo mkdir -p /var/vx/config
sudo ln -sf /var/vx/config /vx/config

sudo ln -s /vx/code/config/read-vx-machine-config.sh /vx/config/read-vx-machine-config.sh

# record the machine type in the configuration (-E keeps the environment variable around, CHOICE prefix sends it in)
CHOICE="${CHOICE}" sudo -E sh -c 'echo "${CHOICE}" > /vx/config/machine-type'

# machine manufacturer
sudo sh -c 'echo "VotingWorks" > /vx/config/machine-manufacturer'

# machine model name i.e. "VxScan"
MODEL_NAME="${MODEL_NAME}" sudo -E sh -c 'echo "${MODEL_NAME}" > /vx/config/machine-model-name'

# code version, e.g. "2021.03.29-d34db33fcd"
GIT_HASH=$(git rev-parse HEAD | cut -c -10) sudo -E sh -c 'echo "$(date +%Y.%m.%d)-${GIT_HASH}" > /vx/code/code-version'

# code tag, e.g. "m11c-rc3"
#GIT_TAG=$(git tag --points-at HEAD) sudo -E sh -c 'echo "${GIT_TAG}" > /vx/code/code-tag'
GIT_TAG="todo" sudo -E sh -c 'echo "${GIT_TAG}" > /vx/code/code-tag'

# qa image flag, 0 (prod image) or 1 (qa image)
IS_QA_IMAGE="${VXADMIN_SUDO}" sudo -E sh -c 'echo "${IS_QA_IMAGE}" > /vx/config/is-qa-image'

# machine ID
sudo sh -c 'echo "0000" > /vx/config/machine-id'

# vx-ui OpenBox configuration
sudo mkdir -p /vx/ui/.config/openbox
sudo ln -s /vx/code/config/openbox-menu.xml /vx/ui/.config/openbox/menu.xml
sudo ln -s /vx/code/config/openbox-rc.xml /vx/ui/.config/openbox/rc.xml

# permissions on directories
sudo chown -R vx-ui:vx-ui /var/vx/ui
sudo chmod -R u=rwX /var/vx/ui
sudo chmod -R go-rwX /var/vx/ui

sudo chown -R vx-admin:vx-admin /var/vx/admin
sudo chmod -R u=rwX /var/vx/admin
sudo chmod -R go-rwX /var/vx/admin

sudo chown -R vx-services:vx-services /var/vx/services
sudo chmod -R u=rwX /var/vx/services
sudo chmod -R go-rwX /var/vx/services

sudo chown -R vx-services:vx-services /var/vx/data
sudo chmod -R u=rwX /var/vx/data
sudo chmod -R go-rwX /var/vx/data

# config readable & executable by all vx users, writable by admin.
sudo chown -R vx-admin:vx-group /var/vx/config
sudo chmod -R u=rwX /var/vx/config
sudo chmod -R g=rX /var/vx/config
sudo chmod -R o-rwX /var/vx/config
#
# TODO: This is a workaround
# Install playwright for cacvote-mark as vx-services user
pushd /vx/code/cacvote/apps/cacvote-mark/backend
sudo -u vx-services pnpm exec playwright install
popd

# non-graphical login
sudo systemctl set-default multi-user.target

# setup auto login
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo cp config/override.conf /etc/systemd/system/getty@tty1.service.d/override.conf
sudo systemctl daemon-reload

# turn off grub
sudo cp config/grub /etc/default/grub
sudo update-grub

# set up the service for the selected machine type
sudo cp systemd-services/${CHOICE}.service /etc/systemd/system/
sudo chmod 644 /etc/systemd/system/${CHOICE}.service
sudo systemctl enable ${CHOICE}.service
sudo systemctl start ${CHOICE}.service

echo "Successfully setup machine."


# now we remove permissions, reset passwords, and ready for production.

USER=$(whoami)

# cleanup
sudo apt autoremove -y
sudo rm -f /var/cache/apt/archives/*.deb
sudo rm -rf /var/tmp/code 
sudo rm -rf /var/tmp/downloads
sudo rm -rf /var/tmp/rust*

# set password for vx-admin
(echo $ADMIN_PASSWORD; echo $ADMIN_PASSWORD) | sudo passwd vx-admin

# add the vx-services user to postgres
current_dir=`pwd`
cd /tmp
sudo -u postgres createuser --superuser "vx-services"
cd ${current_dir}

# We need to schedule a reboot since the vx user will no longer have sudo privileges. 
# One minute is the shortest option, and that's plenty of time for final steps.
sudo shutdown --no-wall -r +1

# disable all passwords
sudo passwd -l root
sudo passwd -l ${USER}
sudo passwd -l vx-ui
sudo passwd -l vx-services

# set a clean hostname
sudo sh -c 'echo "\n127.0.1.1\tVotingWorks" >> /etc/hosts'
sudo hostnamectl set-hostname "VotingWorks" 2>/dev/null

# move in our sudo file, which removes sudo'ing except for granting vx-admin a very specific set of privileges
if [[ "${VXADMIN_SUDO}" == 1 ]] ; then
    sudo cp config/sudoers-for-dev /etc/sudoers
else
    sudo cp config/sudoers /etc/sudoers
fi

# remove everything from this bootstrap user's home directory
cd
rm -rf *
rm -rf .*

# see if this will reclaim space for the zipped image
/usr/bin/sync
ls -altr

echo "Machine setup is complete. Please wait for the VM to reboot."

#-- Just to prevent an active prompt
sleep 60 

exit 0;

