#!/usr/bin/env bash

# The most classic way to create a system is debootstrap. Debootstrap can not be 
# considered a real "container" but included in this repository as an example.
if [ "$#" -eq 2 ] ; then
  # When there are two arguments, the first is range start, the second is range stop.
  RANGE_START=$1
  RANGE_STOP=$2
elif [ "$#" -eq 1 ] ; then
  # When there is only one argument it is the range stop, starting at 1.
  RANGE_START=1
  RANGE_STOP=$1
else
  # When there are no arguments, just create one.
  RANGE_START=1
  RANGE_STOP=1
fi

ARCH=amd64 # $(dpkg-architecture --query DEB_HOST_ARCH)
PACKAGES=dbus,openssh-server,python3-apt,python3-minimal,sudo,vim-tiny
SUITE=buster # $(lsb_release --codename --short)
TARGET=./debootstrap-base
MIRROR=http://httpredir.debian.org/debian

# Prompt the user for the administrator password.
read -s -p "Enter the password for the containers:" UNENCRYPTED_PASSWORD
# Create an encrypted password with mkpasswd --method=sha-512
ENCRYPTED_PASSWORD=$(mkpasswd --method=sha-512 ${UNENCRYPTED_PASSWORD})

sudo apt install -y bridge-utils debootstrap systemd-container

sudo debootstrap \
  --arch=${ARCH} \
  --include=${PACKAGES} \
  ${SUITE} \
  ${TARGET} \
  ${MIRROR}

# Fixup the image
sudo rm -f ${TARGET}/etc/hostname
sudo rm -f ${TARGET}/etc/machine-id
sudo rm -f ${TARGET}/etc/ssh/*_key
echo "nameserver 1.1.1.1" | sudo tee -i ${TARGET}/etc/resolv.conf

# Customize the image
echo -e "${UNENCRYPTED_PASSWORD}\n${UNENCRYPTED_PASSWORD}" | sudo chroot ${TARGET} passwd 
sudo chroot ${TARGET} systemctl enable systemd-networkd
sudo chroot ${TARGET} systemctl enable systemd-resolved
echo "nameserver 127.0.0.53" | sudo tee -i ${TARGET}/etc/resolv.conf 

# Minimize the image
sudo rm -rf ${TARGET}/usr/share/locale/*
sudo rm -rf ${TARGET}/usr/share/doc/*
sudo rm -rf ${TARGET}/lib/udev/hwdb.bin

# Instantiate
echo realhostname | sudo tee -i ${TARGET}/etc/hostname
echo 127.0.1.1 realhostname | tee -a -i ${TARGET}/etc/hosts
sudo chroot ${TARGET} dpkg-reconfigure openssh-server

for NUM in $(seq -w ${RANGE_START} ${RANGE_STOP}); do
  MACHINE_NAME=debootstrap${NUM}
  
  cp -av ${TARGET} ${MACHINE_NAME}
  # Use systemd to start the chroot environment.
  sudo systemd-nspawn --boot --ephemeral --directory=${TARGET} --machine=${MACHINE_NAME}
  # Ephemeral means that nspawn wiill copy the template dir and all changes
  # will be lost when the container stops.
done

echo "Use 'machinectl stop NAME' to stop these systemd \"containers\"."
