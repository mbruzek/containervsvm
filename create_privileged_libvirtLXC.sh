#!/usr/bin/env bash

# Create a number of privileged libvirt-LXC containers that show up in virt-manager.

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
# Use the Elliptic Curve Digital Signature Algorithm standarized by the US government.
ALGORITHM=ecdsa
BANNER_FILE=banner.txt
BEGIN=$(date +%s)
CONTAINER_PREFIX=priv-libvirtLXC
CONTAINER_BASE=${CONTAINER_PREFIX}-base
# Space separated list of package to install on the host.
HOST_PACKAGES="lxc lxc-templates libvirt-daemon-driver-lxc libvirt0 libpam-cgfs bridge-utils debian-archive-keyring uidmap whois"
LXC_ARCH=amd64 # $(dpkg-architecture --query DEB_HOST_ARCH)
LXC_DIST=debian # $(lsb_release --id --short | tr '[:upper:]' '[:lower:]')
LXC_NETWORK="bridge=lxcbr0"  # or network=default
# Comma separated list of packages to install on the guest.
LXC_PACKAGES=openssh-server,python3-apt,python3-minimal,qemu-guest-agent,sudo,vim-tiny
LXC_RAM=1024
LXC_RELEASE=buster # #(lsb_release --codename --short)
LXC_ROOT_DIR=/var/lib/lxc
LXC_TEMPLATE=debian
LXC_VCPUS=2
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
sudo lxc-create --template ${LXC_TEMPLATE} --name ${CONTAINER_BASE} -- --enable-non-free --packages=${LXC_PACKAGES}

# Run commands that edit the root filesystem before the container is started.
echo "Creating the administrator user ${ADMIN}"
sudo chroot ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs /usr/sbin/useradd \
  -c 'The Administrator account' \
  -d ${ADMIN_HOME} \
  -G sudo \
  -m \
  -p ${ENCRYPTED_PASSWORD} \
  -s /bin/bash \
  ${ADMIN}

# Create the administrator user's .ssh directory.
sudo mkdir -p ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs/${ADMIN_HOME}/.ssh
sudo chmod 700 ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs/${ADMIN_HOME}/.ssh

echo "Creating authorized_keys file to allow ssh to this container."
sudo cp -v ${PUBLIC_KEY} ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs/${ADMIN_HOME}/.ssh/authorized_keys

# Create a file to enable passwordless sudo for the Administrator user.
echo "${ADMIN} ALL=(ALL:ALL) NOPASSWD:ALL" > 50-${ADMIN}-NOPASSWD
# Copy the file to the sudoers.d directory.
sudo cp -v 50-${ADMIN}-NOPASSWD ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs/etc/sudoers.d/
rm -v 50-${ADMIN}-NOPASSWD

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
  CONTAINER_PATH=${LXC_ROOT_DIR}/${CONTAINER_NAME}/rootfs

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

  sudo lxc-stop --name ${CONTAINER_NAME}

  FINISH=$(date +%s)
  echo "Customizing ${CONTAINER_NAME} took $(($FINISH-$START)) seconds."

  START=$(date +%s)
  # Install the VM on this system.
  sudo virt-install \
    --autostart \
    --connect lxc:/// \
    --console pty,target_type=serial \
    --description "Libvirt-LXC container created from ${CONTAINER_BASE} on $(date)" \
    --filesystem ${CONTAINER_PATH},/ \
    --memory ${LXC_RAM} \
    --name ${CONTAINER_NAME} \
    --network ${LXC_NETWORK} \
    --noautoconsole \
    --os-type linux \
    --os-variant debiantesting \
    --serial pty \
    --vcpus ${LXC_VCPUS}

  FINISH=$(date +%s)
  echo "Installing ${CONTAINER_NAME} took $(($FINISH-$START)) seconds."
done

# Delete the base container.
sudo lxc-destroy --force --name ${CONTAINER_BASE}

END=$(date +%s)
echo "$(basename $0) script completed in $(($END-$BEGIN)) seconds total."
