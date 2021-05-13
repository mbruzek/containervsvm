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

# The administrator user that will be created.
ADMIN=${USER}
ADMIN_HOME=/home/${ADMIN}
ARCH=amd64 # $(dpkg-architecture --query DEB_HOST_ARCH)
BANNER_FILE=banner.txt
BRIDGE=lxcbr0
PACKAGES=dbus,openssh-server,python3-apt,python3-minimal,sudo,vim-tiny
SUITE=buster # $(lsb_release --codename --short)
CONTAINER_BASE=debootstrap-base
MIRROR=http://httpredir.debian.org/debian

# Ensure the host has the debootstrap and mkpasswd software installed.
sudo apt install -y bridge-utils debootstrap systemd-container whois

# Use the new Elliptic Curve Digital Signature Algorithm standarized by the US government.
ALGORITHM=ecdsa
PRIVATE_KEY=id_${ALGORITHM}
PUBLIC_KEY=id_${ALGORITHM}.pub
# Create a new ssh key to manage the containers.
ssh-keygen -b 521 -t ${ALGORITHM} -P "" -C "${ALGORITHM} ssh key" -f ${PRIVATE_KEY}

# Prompt the user for the administrator password.
read -s -p "Enter the password for the containers:" UNENCRYPTED_PASSWORD
# Create an encrypted password with mkpasswd --method=sha-512
ENCRYPTED_PASSWORD=$(mkpasswd --method=sha-512 ${UNENCRYPTED_PASSWORD})


if [ -d ${CONTAINER_BASE} ]; then
  echo "${CONTAINER_BASE} already exists skipping debootstrap command."
else
  sudo debootstrap \
    --arch=${ARCH} \
    --include=${PACKAGES} \
    ${SUITE} \
    ./${CONTAINER_BASE} \
    ${MIRROR}
fi

# Fixup the image
sudo rm -f ${CONTAINER_BASE}/etc/hostname
sudo rm -f ${CONTAINER_BASE}/etc/machine-id
sudo rm -f ${CONTAINER_BASE}/etc/ssh/*_key
echo "nameserver 1.1.1.1" | sudo tee -i ${CONTAINER_BASE}/etc/resolv.conf

# Customize the image
sudo chroot ${CONTAINER_BASE} systemctl enable systemd-networkd
sudo chroot ${CONTAINER_BASE} systemctl enable systemd-resolved
echo "nameserver 127.0.0.53" | sudo tee -i ${CONTAINER_BASE}/etc/resolv.conf
sudo cp ${BANNER_FILE} ${CONTAINER_BASE}/etc/issue
sudo chroot ${CONTAINER_BASE} ln --symbolic --force /etc/issue /etc/issue.net
sudo chroot ${CONTAINER_BASE} sed -i "s|^#Banner.*|Banner /etc/issue|" /etc/ssh/sshd_config
# Set the root password.
echo -e "${UNENCRYPTED_PASSWORD}\n${UNENCRYPTED_PASSWORD}" | sudo chroot ${CONTAINER_BASE} passwd

BEFORE=$(sudo du -s ${CONTAINER_BASE} | awk '{print $1}')
echo "Size of the ${CONTAINER_BASE} directory before minimization is ${BEFORE}"
# Minimize the image
sudo rm -rf ${CONTAINER_BASE}/usr/share/locale/*
sudo rm -rf ${CONTAINER_BASE}/usr/share/doc/*
sudo rm -rf ${CONTAINER_BASE}/lib/udev/hwdb.bin
AFTER=$(sudo du -s ${CONTAINER_BASE} | awk '{print $1}')
echo "Size of the ${CONTAINER_BASE} directory after minimization is ${AFTER}"

# Instantiate
echo debootstrap-base | sudo tee -i ${CONTAINER_BASE}/etc/hostname
sudo chroot ${CONTAINER_BASE} dpkg-reconfigure openssh-server
sudo chroot ${CONTAINER_BASE} /usr/sbin/useradd \
  -c 'The Administrator account' \
  -d ${ADMIN_HOME} \
  -G sudo \
  -m \
  -p ${ENCRYPTED_PASSWORD} \
  -s /bin/bash \
  ${ADMIN};

# Create the administrator user's .ssh directory.
sudo chroot ${CONTAINER_BASE} mkdir -p ${ADMIN_HOME}/.ssh
echo "Adding ${PUBLIC_KEY} to the authorized_keys file in the container."
sudo cp -v ${PUBLIC_KEY} ${CONTAINER_BASE}/${ADMIN_HOME}/.ssh/authorized_keys
sudo chroot ${CONTAINER_BASE} /bin/chown -R ${ADMIN}:${ADMIN} ${ADMIN_HOME}/.ssh
sudo chroot ${CONTAINER_BASE} /bin/chmod 700 ${ADMIN_HOME}/.ssh

for NUM in $(seq -w ${RANGE_START} ${RANGE_STOP}); do
  MACHINE_NAME=debootstrap${NUM}
  echo "Copying ${CONTAINER_BASE} to ${MACHINE_NAME}"
  sudo cp -a ${CONTAINER_BASE} ./${MACHINE_NAME}
  echo ${MACHINE_NAME} | sudo tee -i ./${MACHINE_NAME}/etc/hostname
  echo 127.0.1.1 ${MACHINE_NAME} | sudo tee -a -i ./${MACHINE_NAME}/etc/hosts
  # Use systemd to start the chroot environment.
  #sudo systemd-nspawn --boot --ephemeral --directory=${CONTAINER_BASE} --machine=${MACHINE_NAME}
  sudo systemd-nspawn --boot --directory=./${MACHINE_NAME} -E LANG=C.UTF-8 -E LC_ALL=C --machine=${MACHINE_NAME} --network-bridge ${BRIDGE}
done

echo "Use 'machinectl stop NAME' to stop these systemd \"containers\"."
