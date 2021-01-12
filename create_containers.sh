#!/usr/bin/env bash

# Create a number of containers using LXC.

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
BEGIN=$(date +%s)

# Comma separated list of packages to install.
PACKAGES="python3-apt,python3-minimal,sudo,vim-tiny"
LXC_ARCH=amd64
LXC_DIST=debian
LXC_RELEASE=buster
LXC_TEMPLATE=debian
LXC_ROOT_DIR=/var/lib/lxc

CONTAINER_PREFIX=lxc
CONTAINER_BASE=${CONTAINER_PREFIX}-base

BANNER_FILE=banner.txt

# Use the new Elliptic Curve Digital Signature Algorithm standarized by the US government.
ALGORITHM=ecdsa
PRIVATE_KEY=id_${ALGORITHM}
PUBLIC_KEY=id_${ALGORITHM}.pub
# Create a new ssh key to manage the containers.
ssh-keygen -b 521 -t ${ALGORITHM} -P "" -C "${ALGORITHM} ssh key" -f ${PRIVATE_KEY}

# Prompt the user for the administrator password.
read -s -p "Enter administrator password for the containers:" UNENCRYPTED_PASSWORD
# Create the encrypted password with mkpasswd --method=sha-512
ENCRYPTED_PASSWORD=$(mkpasswd --method=sha-512 ${UNENCRYPTED_PASSWORD})

# Ensure the LXC software is installed on the host.
sudo apt install lxc lxc-templates libvirt0 libpam-cgfs bridge-utils uidmap

echo "Network setup is required, see: https://wiki.debian.org/LXC#Host-shared_bridge_setup"

START=$(date +%s)

echo "Creating the container ${CONTAINER_BASE} at $(date)"
sudo lxc-create --template ${LXC_TEMPLATE} --name ${CONTAINER_BASE} -- --enable-non-free --packages=${PACKAGES}

# Edit the root filesystem when possible before the container is started.
echo "Creating the administrator user ${ADMIN}"
sudo chroot ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs /usr/sbin/useradd -c Administrator -d ${ADMIN_HOME} -G sudo -m -s /bin/bash -p ${ENCRYPTED_PASSWORD} ${ADMIN};

sudo mkdir -p ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs/${ADMIN_HOME}/.ssh
sudo chmod 700 ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs/${ADMIN_HOME}/.ssh
echo "Creating authorized_keys file to allow ssh to this container."
sudo cp -v ${PUBLIC_KEY} ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs/${ADMIN_HOME}/.ssh/authorized_keys

# Copy the banner file to the container.
sudo cp -v ${BANNER_FILE} ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs/etc/${BANNER_FILE}
# Modify sshd_config to use the baner file.
sudo sed -i "s|^#Banner.*|Banner /etc/${BANNER_FILE}|" ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs/etc/ssh/sshd_config
# Create links to the banner file with /etc/issue and /etc/issue.net
sudo chroot ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs /usr/bin/ln -s -f /etc/${BANNER_FILE} /etc/issue
sudo chroot ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs /usr/bin/ln -s -f /etc/${BANNER_FILE} /etc/issue.net

FINISH=$(date +%s)
echo "Creating ${CONTAINER_BASE} took $(($FINISH-$START)) seconds."

# Loop in a sequence for the desired number of containers.
for NUM in $(seq -w ${RANGE_START} ${RANGE_STOP}); do
  START=$(date +%s)

  CONTAINER_NAME=${CONTAINER_PREFIX}${NUM}

  echo "Starting customization of ${CONTAINER_NAME} at $(date)"
  sudo lxc-copy --name ${CONTAINER_BASE} --newname=${CONTAINER_NAME}

  # Start the container and run the init process.
  sudo lxc-start --name ${CONTAINER_NAME}

  # Loop until the command does not return an error.
  sudo lxc-attach -n ${CONTAINER_NAME} -- bash -c 'while $(systemctl is-system-running &>/dev/null); (($?==1)); do :; done'
  # Wait for the system to fully start.
  sudo lxc-attach -n ${CONTAINER_NAME} -- systemctl is-system-running --wait

  echo "Changing ownership of the .ssh directory to ${ADMIN}"
  sudo lxc-attach -n ${CONTAINER_NAME} -- chown -R ${ADMIN}:${ADMIN} ${ADMIN_HOME}/.ssh

  echo "Setting the root password"
  echo -e "${UNENCRYPTED_PASSWORD}\n${UNENCRYPTED_PASSWORD}" | sudo lxc-attach -n ${CONTAINER_NAME} -- passwd

  echo "Changing the hostname to ${CONTAINER_NAME}"
  sudo lxc-attach -n ${CONTAINER_NAME} -- hostname ${CONTAINER_NAME}

  FINISH=$(date +%s)
  echo "Customization of ${CONTAINER_NAME} took $(($FINISH-$START)) seconds."
done

# Delete the base container.
sudo lxc-destroy --force --name ${CONTAINER_BASE}

END=$(date +%s)
echo "$(basename $0) script completed in $(($END-$BEGIN)) seconds total."
