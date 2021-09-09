#!/usr/bin/env bash

# Create a number of privileged LXC containers.

# Privileged containers are defined as any countainer where the container uid 0
# is mapped to the host's uid 0. In such containers, protection of the host
# and prevention of escape is entirely done through Mandatory Access Control
# (apparmor, selinux), seccomp filters, dropping of capabilities and namespaces.

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
# Use the Elliptic Curve Digital Signature Algorithm standardized by the US government.
ALGORITHM=ecdsa
BANNER_FILE=banner.txt
BEGIN=$(date +%s)
CONTAINER_PREFIX=priv-LXC
CONTAINER_BASE=${CONTAINER_PREFIX}-base
# Space separated list of packages to install on the host.
HOST_PACKAGES="lxc lxc-templates libvirt0 libpam-cgfs bridge-utils debian-archive-keyring uidmap whois"
LXC_ARCH=amd64 # $(dpkg-architecture --query DEB_HOST_ARCH)
LXC_DIST=debian # $(lsb_release --id --short | tr '[:upper:]' '[:lower:]')
# Comma separated list of packages to install.
LXC_PACKAGES=openssh-server,python3-apt,python3-minimal,sudo,vim-tiny
LXC_RELEASE=bullseye # #(lsb_release --codename --short)
LXC_ROOT_DIR=/var/lib/lxc
LXC_TEMPLATE=debian
PRIVATE_KEY=id_${ALGORITHM}
PUBLIC_KEY=id_${ALGORITHM}.pub

# Create a new ssh key to manage the containers.
ssh-keygen -b 521 -t ${ALGORITHM} -P "" -C "${ALGORITHM} ssh key" -f ${PRIVATE_KEY}

# Ensure the LXC software and mkpasswd is installed on the host.
sudo apt install -y ${HOST_PACKAGES}

# Prompt the user for the administrator password.
read -s -p "Enter the password for the containers:" UNENCRYPTED_PASSWORD
# Create an encrypted password with mkpasswd --method=sha-512
ENCRYPTED_PASSWORD=$(mkpasswd --method=sha-512 ${UNENCRYPTED_PASSWORD})

echo "Network setup is required, see: https://wiki.debian.org/LXC#Host-shared_bridge_setup"

START=$(date +%s)

echo "Creating the container ${CONTAINER_BASE} at $(date)"
sudo lxc-create --template ${LXC_TEMPLATE} --name ${CONTAINER_BASE} -- --enable-non-free --packages=${LXC_PACKAGES} --release ${LXC_RELEASE}

# Run commands that edit the root filesystem before the container is started.
echo "Creating the administrator user ${ADMIN}"
sudo chroot ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs /usr/sbin/useradd \
  -c 'The Administrator account' \
  -d ${ADMIN_HOME} \
  -G sudo \
  -m \
  -p ${ENCRYPTED_PASSWORD} \
  -s /bin/bash \
  ${ADMIN};

# Create the administrator user's .ssh directory.
sudo mkdir -p ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs/${ADMIN_HOME}/.ssh
sudo chmod 700 ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs/${ADMIN_HOME}/.ssh

echo "Creating authorized_keys file to allow ssh to this container."
sudo cp -v ${PUBLIC_KEY} ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs/${ADMIN_HOME}/.ssh/authorized_keys

# Create a file to enable passwordless sudo for the Administrator user.
echo "${ADMIN} ALL=(ALL:ALL) NOPASSWD:ALL" | sudo tee -i ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs/etc/sudoers.d/50-${ADMIN}-NOPASSWD

# Copy the banner file to the container.
sudo cp -v ${BANNER_FILE} ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs/etc/issue
# Modify sshd_config to use the baner file.
sudo sed -i "s|^#Banner.*|Banner /etc/issue|" ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs/etc/ssh/sshd_config
# Create symbolic link to the /etc/issue and /etc/issue.net
sudo chroot ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs /usr/bin/ln -s -f /etc/issue /etc/issue.net

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
  sudo lxc-attach --name ${CONTAINER_NAME} -- bash -c 'while $(systemctl is-system-running &>/dev/null); (($?==1)); do :; done'
  # Wait for the system to fully start.
  sudo lxc-attach --name ${CONTAINER_NAME} -- systemctl is-system-running --wait

  echo "Changing ownership of the .ssh directory to ${ADMIN}"
  sudo lxc-attach --name ${CONTAINER_NAME} -- chown -R ${ADMIN}:${ADMIN} ${ADMIN_HOME}/.ssh

  echo "Setting the root password"
  echo -e "${UNENCRYPTED_PASSWORD}\n${UNENCRYPTED_PASSWORD}" | sudo lxc-attach --name ${CONTAINER_NAME} -- passwd

  echo "Changing the hostname to ${CONTAINER_NAME}"
  sudo lxc-attach --name ${CONTAINER_NAME} -- hostname ${CONTAINER_NAME}

  FINISH=$(date +%s)
  echo "Customizing ${CONTAINER_NAME} took $(($FINISH-$START)) seconds."
done

# Delete the base container.
sudo lxc-destroy --force --name ${CONTAINER_BASE}

END=$(date +%s)
echo "$(basename $0) script completed in $(($END-$BEGIN)) seconds total."
