#!/bin/bash

if [[ $EUID -eq 0 ]]; then
  echo "ERROR: This script should not be run via sudo."
  exit 1
fi

local_user=`logname`
local_user_home_dir=$( getent passwd "${local_user}" | cut -d: -f6 )
vxsuite_build_system_dir="${local_user_home_dir}/code/vxsuite-build-system"
complete_system_dir="${local_user_home_dir}/code/vxsuite-complete-system"
pollbook_config_files_dir="${vxsuite_build_system_dir}/scripts/pollbook-files"
build_dir="/home/vx/build"
standard_config_files_dir="${build_dir}/config"
app_scripts_dir="${build_dir}/app-scripts"


set -euo pipefail

echo "Welcome to the VxPollbook setup script."
echo "THIS IS A DESTRUCTIVE SCRIPT. Ctrl+C now to cancel."
sleep 5
echo "Preparing to set up the pollbook machine..."
echo 

read -p "Is this image for QA, where you want sudo privileges, terminal access via TTY2, and the ability to record screengrabs? [y/N] " qa_image_flag

IS_RELEASE_IMAGE=0

if [[ $qa_image_flag == 'y' || $qa_image_flag == 'Y' ]]; then
    IS_QA_IMAGE=1
    VENDOR_PASSWORD='insecure'
    echo "OK, creating a QA image with sudo privileges for the vx-vendor user and terminal access via TTY2."
    echo "Using password insecure for the vx-vendor user."
else
    IS_QA_IMAGE=0
    echo "Ok, creating a production image. No sudo privileges for anyone!"
    echo
        read -p "Is this additionally an official release image? [y/N] " release_image_flag
    if [[ "${release_image_flag}" == 'y' || "${release_image_flag}" == 'Y' ]]; then
        read -p "Are you sure? [y/N] " confirm_release_image_flag
        if [[ "${confirm_release_image_flag}" == 'y' || "${confirm_release_image_flag}" == 'Y' ]]; then
            IS_RELEASE_IMAGE=1
pollbook_config_files_dir="${vxsuite_build_system_dir}/scripts/pollbook-files"
            VERSION="$(< ${pollbook_config_files_dir}/VERSION)"
            echo "OK, will set the displayed code version to: ${VERSION}"
        else
            echo "OK, not an official release image."
        fi
    else
        echo "OK, not an official release image."
    fi

    echo "Next, we need to set a password for the vx-vendor user."
    while true; do
        read -s -p "Set vx-vendor password: " VENDOR_PASSWORD
        echo
        read -s -p "Confirm vx-vendor password: " CONFIRM_PASSWORD
        echo
        if [[ "${VENDOR_PASSWORD}" = "${CONFIRM_PASSWORD}" ]]
        then
            echo "Password confirmed."
            break
        else
            echo "Passwords do not match, try again."
        fi
    done

    echo
fi

echo
echo "The script will take it from here and set up the machine."
echo

# TODO: Uncomment after secure boot / prod testing is complete
#       It's just easier to have tty2 for troubleshooting w/o vendor card process
# Disable terminal access via TTY2 for production images
#if [[ "${IS_QA_IMAGE}" == 0 ]]
#then
    #sudo cp config/11-disable-tty.conf /etc/X11/xorg.conf.d/
#fi

sudo chown :lpadmin /sbin/lpinfo
echo "export PATH=$PATH:/sbin" | sudo tee -a /etc/bash.bashrc

# turn off automatic updates
sudo cp $standard_config_files_dir/20auto-upgrades /etc/apt/apt.conf.d/

# make sure machine never shuts down on idle, and does shut down on power key (no hibernate or anything.)
sudo cp $standard_config_files_dir/logind.conf /etc/systemd/

echo "Creating necessary directories"
# directory structure
sudo mkdir -p /vx
sudo mkdir -p /var/vx
sudo mkdir -p /var/vx/data/pollbook
sudo mkdir -p /var/vx/ui
sudo mkdir -p /var/vx/vendor
sudo mkdir -p /var/vx/services
sudo mkdir -p /var/vx/scripts

sudo ln -sf /var/vx/data /vx/data

# mutable homedirs because we haven't figured out how to do this well yet.
sudo ln -sf /var/vx/ui /vx/ui
sudo ln -sf /var/vx/vendor /vx/vendor
sudo ln -sf /var/vx/services /vx/services
sudo ln -sf /var/vx/scripts /vx/scripts

echo "Creating users"
# create users, no common group, specified uids.
id -u vx-ui &> /dev/null || sudo useradd -u 1751 -m -d /var/vx/ui -s /bin/bash vx-ui
id -u vx-vendor &> /dev/null || sudo useradd -u 1752 -m -d /var/vx/vendor -s /bin/bash vx-vendor
id -u vx-services &> /dev/null || sudo useradd -u 1750 -m -d /var/vx/services vx-services

# a vx group for all vx users
getent group vx-group || sudo groupadd -g 800 vx-group
sudo usermod -aG vx-group vx-ui
sudo usermod -aG vx-group vx-vendor
sudo usermod -aG vx-group vx-services

sudo usermod -aG video vx-ui
sudo usermod -aG audio vx-ui
sudo usermod -aG audio vx-services

# remove all files created by default
sudo rm -rf /vx/services/* /vx/ui/* /vx/vendor/*

# Let all of our users read logs
sudo usermod -aG adm vx-ui
sudo usermod -aG adm vx-vendor
sudo usermod -aG adm vx-services

# Add groups needed for barcode scanner to vx-services user
sudo usermod -aG dialout vx-services
sudo usermod -aG plugdev vx-services

# Set up log config
(cd $complete_system_dir && sudo bash setup-scripts/setup-logging.sh)

# set up mount point ahead of time because read-only later
sudo mkdir -p /media/vx/usb-drive
sudo chown -R vx-ui:vx-group /media/vx

# let vx-services manage printers
sudo usermod -aG lpadmin vx-services

# Strongswan config and apparmor profile
sudo cp "$pollbook_config_files_dir/swanmesh.conf" /etc/swanctl/conf.d/.
sudo cp "$pollbook_config_files_dir/apparmor.d/usr.sbin.swanctl" /etc/apparmor.d/.

# Move mesh network configuration files
sudo cp "$pollbook_config_files_dir/setup_basic_mesh.sh" /vx/scripts/.
sudo cp "$pollbook_config_files_dir/join-mesh-network.service" /etc/systemd/system/.
sudo cp "$pollbook_config_files_dir/avahi-autoipd.service" /etc/systemd/system/.
sudo cp "$pollbook_config_files_dir/99-mesh-network.rules" /etc/udev/rules.d/.

# Barcode scanner udev rules
sudo cp "$pollbook_config_files_dir/70-ts100-plugdev-usb.rules" /etc/udev/rules.d/.
sudo cp "$pollbook_config_files_dir/99-ts100-dialout-tty.rules" /etc/udev/rules.d/.

### set up CUPS to read/write all config out of /var to be compatible with read-only root filesystem

# copy existing cups config structure to new /var location
sudo mkdir /var/etc
sudo cp -rp /etc/cups /var/etc/
sudo rm -rf /etc/cups

# set up cups config files that internally include appropriate paths with /var
sudo cp $standard_config_files_dir/cupsd.conf /var/etc/cups/
sudo cp $standard_config_files_dir/cups-files.conf /var/etc/cups/

# modify cups systemd service to read config files from /var
sudo cp $standard_config_files_dir/cups.service /usr/lib/systemd/system/

# modified apparmor profiles to allow cups to access config files in /var
sudo cp $standard_config_files_dir/apparmor.d/usr.sbin.cupsd /etc/apparmor.d/

# copy any modprobe configs we might use
sudo cp $standard_config_files_dir/modprobe.d/10-i915.conf /etc/modprobe.d/
sudo cp $standard_config_files_dir/modprobe.d/50-bluetooth.conf /etc/modprobe.d/

# load the i915 display module as early as possible
sudo sh -c 'echo "i915" >> /etc/modules-load.d/modules.conf'

# On non-vsap systems, there can be varying levels of screen flickering
# depending on the system components. To fix it, we use an xorg config
# that switches the acceleration method to uxa instead of sna
# Note: The logic below is not an ideal long-term solution since it's 
# possible a future mark or mark-scan system would also have this issue.
# As of now (202402725), we use VSAP units that do not exhibit flickering
# and applying this change can not be used on them without causing other
# undesireable graphical behaviors. Longer term, it would be better to 
# detect during initial boot whether to apply this xorg config.
sudo cp $standard_config_files_dir/10-intel-xorg.conf /etc/X11/xorg.conf.d/10-intel.conf

echo "Setting up the code"
sudo mv $build_dir /vx/code

# symlink the code and run-*.sh in /vx/services
sudo ln -s /vx/code/vxpollbook /vx/services/vxpollbook
sudo ln -s /vx/code/run-vxpollbook.sh /vx/services/run-vxpollbook.sh

# symlink to vxsuite so paths dont break
sudo ln -s /vx/code/vxpollbook /vx/code/vxsuite

# symlink appropriate vx/ui files
sudo ln -s /vx/code/config/ui_bash_profile /vx/ui/.bash_profile
sudo ln -s /vx/code/config/Xresources /vx/ui/.Xresources
sudo ln -s /vx/code/config/xinitrc /vx/ui/.xinitrc

# symlink the GTK .settings.ini
sudo mkdir -p /vx/ui/.config/gtk-3.0
sudo ln -s /vx/code/config/gtksettings.ini /vx/ui/.config/gtk-3.0/settings.ini

# vendor user setup 
sudo ln -s /vx/code/config/admin_bash_profile /vx/vendor/.bash_profile
sudo ln -s /vx/code/config/vendor-functions /vx/vendor/vendor-functions

# Make sure our cmdline file is readable by vx-vendor
sudo mkdir -p /vx/vendor/config
sudo cp ${complete_system_dir}/config/cmdline /vx/code/config/cmdline
sudo cp ${complete_system_dir}/config/grub.cfg /vx/code/config/grub.cfg
sudo ln -s /vx/code/config/cmdline /vx/vendor/config/cmdline
sudo ln -s /vx/code/config/grub.cfg /vx/vendor/config/grub.cfg

# dm-verity initramfs hooks
sudo cp ${complete_system_dir}/config/dmverity-root.hook /etc/initramfs-tools/hooks/dmverity-root
sudo cp ${complete_system_dir}/config/dmverity-root.script /etc/initramfs-tools/scripts/local-premount/dmverity-root

# All our logo files are 16-color BMP files. VxScan requires an 800x600 image, per
# https://up-shop.org/up-bios-splash-service.html
sudo cp /vx/code/config/logo-horizontal.bmp /vx/code/config/logo.bmp
sudo ln -s /vx/code/config/logo.bmp /vx/vendor/config/logo.bmp

# machine configuration
sudo mkdir -p /var/vx/config
sudo mkdir /var/vx/config/app-flags
sudo ln -sf /var/vx/config /vx/config

sudo ln -s /vx/code/config/read-vx-machine-config.sh /vx/config/read-vx-machine-config.sh

# To support new images installed via older vx-iso releases
# explicitly set the EXPAND_VAR flag file
# (This gets set by new vx-iso releases, so we can eventually remove
# setting the flag here, but it doesn't hurt to leave it)
sudo touch /vx/config/EXPAND_VAR

# machine manufacturer
sudo sh -c 'echo "VotingWorks" > /vx/config/machine-manufacturer'

# machine model name i.e. "VxScan"
sudo -E sh -c 'echo "VxPollbook" > /vx/config/machine-model-name'
sudo -E sh -c 'echo "poll-book" > /vx/config/machine-type'

# code version, e.g. "2021.03.29-d34db33fcd"
GIT_HASH=$(git rev-parse HEAD | cut -c -10) sudo -E sh -c 'echo "$(date +%Y.%m.%d)-${GIT_HASH}" > /vx/code/code-version'

if [[ "${IS_RELEASE_IMAGE}" == 1 ]]; then
    # Still keep the full code version for reference
    sudo cp /vx/code/code-version /vx/code/code-version-full
    # But use the nicely formatted version, e.g., "v4.0.0", for display
    VERSION="${VERSION}" sudo -E sh -c 'echo "${VERSION}" > /vx/code/code-version'
fi

# code tag, e.g. "m11c-rc3"
GIT_TAG=$(git tag --points-at HEAD) sudo -E sh -c 'echo "${GIT_TAG}" > /vx/code/code-tag'

# qa image flag, 0 (prod image) or 1 (qa image)
IS_QA_IMAGE="${IS_QA_IMAGE}" sudo -E sh -c 'echo "${IS_QA_IMAGE}" > /vx/config/is-qa-image'

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

sudo chown -R vx-vendor:vx-vendor /var/vx/vendor
sudo chmod -R u=rwX /var/vx/vendor
sudo chmod -R go-rwX /var/vx/vendor

sudo chown -R vx-services:vx-services /var/vx/services
sudo chmod -R u=rwX /var/vx/services
sudo chmod -R go-rwX /var/vx/services

sudo chown -R vx-services:vx-services /var/vx/data
sudo chmod -R u=rwX /var/vx/data
sudo chmod -R go-rwX /var/vx/data

# Config is writable by the vx-vendor user and readable/executable by all vx-* users, with the
# exception of the app-flags subdirectory and /vx/config/openssl.cnf, which are special-cased to be
# writable by all vx-* users
sudo chown -R vx-vendor:vx-group /var/vx/config
sudo chmod -R u=rwX /var/vx/config
sudo chmod -R g=rX /var/vx/config
sudo chmod -R g=rwX /var/vx/config/app-flags
sudo chmod -R o-rwX /var/vx/config

sudo cp /etc/ssl/openssl.cnf /etc/ssl/openssl.default.cnf
sudo sed -i 's|^\.include /etc/ssl/openssl\.cnf$|.include /etc/ssl/openssl.default.cnf|' \
    /vx/code/vxsuite/libs/auth/config/openssl.vx.cnf
sudo ln -fs /etc/ssl/openssl.default.cnf /vx/config/openssl.cnf
sudo ln -fs /vx/config/openssl.cnf /etc/ssl/openssl.cnf
sudo chown -h vx-vendor:vx-group /vx/config/openssl.cnf

# Pollbook has mesh networking functionality
# This requires modifying files on the read-only root filesystem
# so we create a symlink structure to enable writes to those files
sudo mkdir -p /vx/config/etc

# Pollbook: Host/Hostname links
sudo mv /etc/hosts /vx/config/etc/hosts
sudo ln -fs /vx/config/etc/hosts /etc/hosts
sudo mv /etc/hostname /vx/config/etc/hostname
sudo ln -fs /vx/config/etc/hostname /etc/hostname

# Pollbook: strongswan links
sudo mv /etc/swanctl/ /vx/config/etc/
sudo ln -fs /vx/config/etc/swanctl /etc/swanctl

sudo cp ${complete_system_dir}/config/interfaces /etc/network/interfaces

# non-graphical login
sudo systemctl set-default multi-user.target

# setup auto login
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo cp /vx/code/config/override.conf /etc/systemd/system/getty@tty1.service.d/override.conf
sudo systemctl daemon-reload

# turn off grub
sudo cp /vx/code/config/grub /etc/default/grub
sudo update-grub

# turn off network time sync
sudo timedatectl set-ntp no

# set up symlinked timezone files to prepare for read-only filesystem
sudo rm -f /etc/localtime
sudo ln -sf /usr/share/zoneinfo/America/Chicago /vx/config/localtime
sudo ln -sf /vx/config/localtime /etc/localtime

# remove all network drivers. Buh bye.
# sudo apt purge -y network-manager > /dev/null 2>&1 || true
# sudo rm -rf /lib/modules/*/kernel/drivers/net/*

# delete any remembered existing network connections (e.g. wifi passwords)
sudo rm -f /etc/NetworkManager/system-connections/*

# set up the service for the selected machine type
sudo cp $pollbook_config_files_dir/vxpollbook.service /etc/systemd/system/
sudo chmod 644 /etc/systemd/system/vxpollbook.service
sudo systemctl daemon-reload
sudo systemctl enable vxpollbook.service
sudo systemctl start vxpollbook.service

# set up the barcode scanner service
sudo cp $pollbook_config_files_dir/barcode-scanner-daemon.service /etc/systemd/system/
sudo cp $pollbook_config_files_dir/run-barcode-scanner-daemon.sh /vx/code/.
sudo ln -s /vx/code/run-barcode-scanner-daemon.sh /vx/services/run-barcode-scanner-daemon.sh
sudo chmod 644 /etc/systemd/system/barcode-scanner-daemon.service
sudo systemctl daemon-reload
sudo systemctl enable barcode-scanner-daemon.service
sudo systemctl start barcode-scanner-daemon.service


# To provide a boot sequence with as few console logs as possible
# we suppress the messages from the login command
for user in vx-vendor vx-ui
do
  user_home_dir=$( getent passwd "${user}" | cut -d: -f6 )
  sudo touch ${user_home_dir}/.hushlogin
  sudo chown ${user}:${user} ${user_home_dir}/.hushlogin
done

# We need to disable pulseaudio for users since it runs per user
# We manually start the pulseaudio service within vxsuite for the vx-ui user
# Note: Depending on future use-cases, we may need to disable pulseaudio 
# for the vx-services user. It is not currently necessary though.
for user in vx-vendor vx-ui
do
  user_home_dir=$( getent passwd "${user}" | cut -d: -f6 )
  sudo mkdir -p ${user_home_dir}/.config/systemd/user
  sudo ln -s /dev/null ${user_home_dir}/.config/systemd/user/pulseaudio.service
  sudo ln -s /dev/null ${user_home_dir}/.config/systemd/user/pulseaudio.socket
  sudo chown -R ${user}:${user} ${user_home_dir}/.config
done

# We suspend pulseaudio idling via ~vx-ui/.xinitrc, but, anecdotally, it seems
# like there is a race condition that can result in the pulseaudio config
# still idling audio in the event of a USB error during X initialization
# Rather than applying a work-around at the system level, we configure
# the vx-ui user to always suspend, regardless of any USB errors during boot
# according to pulseaudio best practices
vx_ui_homedir=$( getent passwd vx-ui | cut -d: -f6 )
sudo mkdir -p ${vx_ui_homedir}/.config/pulse
sudo tee ${vx_ui_homedir}/.config/pulse/default.pa > /dev/null << 'PULSE'
.include /etc/pulse/default.pa
.nofail
unload-module module-suspend-on-idle
.fail
PULSE

# Fix permissions so vx-ui owns the pulseaudio config
sudo chown -R vx-ui:vx-ui ${vx_ui_homedir}/.config/pulse

# Enable the mesh network and related services
sudo udevadm control --reload-rules
sudo systemctl daemon-reload
sudo systemctl enable join-mesh-network
sudo systemctl enable avahi-daemon
sudo systemctl enable avahi-autoipd

sudo systemctl start avahi-autoipd

echo "Successfully setup machine."

# now we remove permissions, reset passwords, and ready for production.

# cleanup
sudo apt remove -y git firefox snapd > /dev/null 2>&1 || true
sudo apt autoremove -y > /dev/null 2>&1 || true
sudo rm -f /var/cache/apt/archives/*.deb
sudo rm -rf /var/tmp/code 
sudo rm -rf /var/tmp/downloads
sudo rm -rf /var/tmp/rust*

# set password for vx-vendor
(echo $VENDOR_PASSWORD; echo $VENDOR_PASSWORD) | sudo passwd vx-vendor

# We need to schedule a reboot since the vx user will no longer have sudo privileges. 
# One minute is the shortest option, and that's plenty of time for final steps.
sudo shutdown --no-wall -r +1

# disable all passwords
sudo passwd -l root
sudo passwd -l ${local_user}
sudo passwd -l vx-ui
sudo passwd -l vx-services

# set a clean hostname
sudo sh -c 'echo "\n127.0.1.1\tVotingWorks" >> /etc/hosts'
#sudo hostnamectl set-hostname "VotingWorks" 2>/dev/null
# We can't use hostnamectl because it recreates /etc/hostname as a file
# breaking the symlink, which we need for secure boot
# Instead, directly edit the file and use the hostname command
# Note: choose-vx-machine-id.sh also uses this approach now
sudo sh -c 'echo "VotingWorks" > /etc/hostname'
sudo hostname VotingWorks

# Copy firewalld config to log denied connection attempts
sudo cp ${pollbook_config_files_dir}/firewalld.conf /etc/firewalld/.

# The symlink approach results in a hostname of localhost
# because it's not available early enough in the boot process
# This simple service sets the hostname from the symlink
sudo cp ${pollbook_config_files_dir}/early-hostname.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable early-hostname.service

if [[ "${IS_QA_IMAGE}" == 1 ]]; then
    sudo cp \
      /vx/code/vxpollbook/libs/auth/certs/dev/vx-cert-authority-cert.pem \
      /vx/code/vxpollbook/libs/auth/certs/prod/vx-cert-authority-cert.pem
fi

# Set up a one-time run of fstrim to reduce VM size
sudo cp /vx/code/config/vm-fstrim.service /etc/systemd/system/
sudo systemctl enable vm-fstrim.service

# NOTE: you cannot use sudo commands after this runs
if [[ "${IS_QA_IMAGE}" == 1 ]]; then
  sudo cp ${pollbook_config_files_dir}/sudoers-for-dev /etc/sudoers
else
  sudo cp ${pollbook_config_files_dir}/sudoers /etc/sudoers
fi

# NOTE AGAIN: no more sudo commands below this line. Privileges have been removed.

# remove everything from this bootstrap user's home directory
cd ${local_user_home_dir}
rm -rf *
rm -rf .*

echo "Machine setup is complete. Please wait for the VM to reboot."

#-- Just to prevent an active prompt
sleep 60 

exit 0;
