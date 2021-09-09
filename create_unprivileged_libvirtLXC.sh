#!/usr/bin/env bash

# Create a number of libvirt-LXC containers, that show up in virt-manager.

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
BRIDGE=lxcbr0
CONTAINER_PREFIX=unpriv-libvirtLXC
CONTAINER_BASE=${CONTAINER_PREFIX}-base
# Space separated list of packages to install on the host.
HOST_PACKAGES="lxc lxc-templates libvirt-daemon-driver-lxc libvirt0 libpam-cgfs bridge-utils debian-archive-keyring uidmap whois"
KEYSERVER="pgp.mit.edu"
LXC_ARCH=amd64 # $(dpkg-architecture --query DEB_HOST_ARCH)
LXC_DIST=debian # $(lsb_release --id --short | tr '[:upper:]' '[:lower:]')
LXC_NETWORK="bridge=${BRIDGE}"  # or network=default
# Space separated list of packages to install on the guest.
LXC_PACKAGES="openssh-server python3-apt python3-minimal qemu-guest-agent sudo vim-tiny"
LXC_RAM=1024
LXC_RELEASE=bullseye # #(lsb_release --codename --short)
LXC_ROOT_DIR=${HOME}/.local/share/lxc
LXC_TEMPLATE=download
LXC_VCPUS=2
PRIVATE_KEY=id_${ALGORITHM}
PUBLIC_KEY=id_${ALGORITHM}.pub

# Create a new ssh key to manage the containers.
ssh-keygen -b 521 -t ${ALGORITHM} -P "" -C "${ALGORITHM} ssh key" -f ${PRIVATE_KEY}

# Ensure the LXC software and mkpasswd is installed on the host.
sudo apt install -y ${HOST_PACKAGES}
sudo systemctl restart libvirtd

# Prompt the user for the administrator password.
read -s -p "Enter the password for the containers:" UNENCRYPTED_PASSWORD
# Create an encrypted password with mkpasswd --method=sha-512
ENCRYPTED_PASSWORD=$(mkpasswd --method=sha-512 ${UNENCRYPTED_PASSWORD})

# All the kernel to create unprivileged user namespace clones.
sudo sh -c 'echo "kernel.unprivileged_userns_clone=1" > /etc/sysctl.d/80-lxc-userns.conf'
sudo systemctl restart systemd-sysctl

# Unprivileged containers can not run without access to the lxc root directory.
sudo setfacl -m u:100000:x ${HOME} ${HOME}/.local ${HOME}/.local/share

# Create the userid mapping for unprivileged containers.
mkdir -p ${HOME}/.config/lxc
echo "lxc.include = /etc/lxc/default.conf" > ${HOME}/.config/lxc/default.conf
echo "lxc.idmap = u 0 100000 65536" >> ${HOME}/.config/lxc/default.conf
echo "lxc.idmap = g 0 100000 65536" >> ${HOME}/.config/lxc/default.conf
# # Configure the network type and link.
# echo "lxc.network.type = veth" >> ${HOME}/.config/lxc/default.conf
# echo "lxc.network.link = lxcbr0" >> ${HOME}/.config/lxc/default.conf
# User, type, device, limit
echo "${ADMIN} veth ${BRIDGE} 1024" | sudo tee -i /etc/lxc/lxc-usernet

START=$(date +%s)

echo "Creating the container ${CONTAINER_BASE} at $(date)"
lxc-create --template ${LXC_TEMPLATE} --name ${CONTAINER_BASE} -- --arch ${LXC_ARCH} --dist ${LXC_DIST} --keyserver ${KEYSERVER} --release ${LXC_RELEASE}

# Disable ipv6 on the base container.
cat << EOF | tee -i ${LXC_ROOT_DIR}/${CONTAINER_BASE}/rootfs/etc/sysctl.d/50-disable-ipv6.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

# Star the container running.
lxc-start --name ${CONTAINER_BASE}

# Wait for container to start networking.
sleep 5

echo "Setting the root password"
echo -e "${UNENCRYPTED_PASSWORD}\n${UNENCRYPTED_PASSWORD}" | lxc-attach -n ${CONTAINER_BASE} -- passwd

# Run commands that edit the root filesystem before the container is started.
echo "Creating the administrator user ${ADMIN}"
lxc-attach --name ${CONTAINER_BASE} -- /usr/sbin/useradd \
  -c 'The Administrator account' \
  -d ${ADMIN_HOME} \
  -G sudo \
  -m \
  -p ${ENCRYPTED_PASSWORD} \
  -s /bin/bash \
  ${ADMIN}

cat ${BANNER_FILE} | lxc-attach --name ${CONTAINER_BASE} -- tee -i /etc/banner.txt
lxc-attach --name ${CONTAINER_BASE} -- ln -s -f /etc/banner.txt /etc/issue
lxc-attach --name ${CONTAINER_BASE} -- ln -s -f /etc/banner.txt /etc/issue.net

# Create the administrator user's .ssh directory.
lxc-attach --name ${CONTAINER_BASE} -- mkdir -p ${ADMIN_HOME}/.ssh
cat ${PUBLIC_KEY} | lxc-attach --name ${CONTAINER_BASE} -- tee -a -i ${ADMIN_HOME}/.ssh/authorized_keys
lxc-attach --name ${CONTAINER_BASE} -- chmod 700 ${ADMIN_HOME}/.ssh
lxc-attach --name ${CONTAINER_BASE} -- chown -R ${ADMIN}:${ADMIN} ${ADMIN_HOME}/.ssh

lxc-attach --name ${CONTAINER_BASE} -- apt install -y ${LXC_PACKAGES}

lxc-attach --name ${CONTAINER_BASE} -- sed -i "s|^#Banner.*|Banner /etc/banner.txt|" /etc/ssh/sshd_config

# Create a file to enable passwordless sudo for the Administrator user.
echo "${ADMIN} ALL=(ALL:ALL) NOPASSWD:ALL" | lxc-attach --name ${CONTAINER_BASE} -- tee -i /etc/sudoers.d/50-${ADMIN}-NOPASSWD

lxc-stop --name ${CONTAINER_BASE}

FINISH=$(date +%s)
echo "Creating ${CONTAINER_BASE} took $(($FINISH-$START)) seconds."

# Loop in a sequence for the desired number of containers.
for NUM in $(seq -w ${RANGE_START} ${RANGE_STOP}); do
  START=$(date +%s)

  CONTAINER_NAME=${CONTAINER_PREFIX}${NUM}
  CONTAINER_PATH=${LXC_ROOT_DIR}/${CONTAINER_NAME}/rootfs

  echo "Starting customization of ${CONTAINER_NAME} at $(date)"
  lxc-copy --name ${CONTAINER_BASE} --newname=${CONTAINER_NAME}

  echo "Changing the hostname to ${CONTAINER_NAME}"
  sudo sed -i "s|${CONTAINER_BASE}|${CONTAINER_NAME}|" ${CONTAINER_PATH}/etc/hostname
  sudo sed -i "s|${CONTAINER_BASE}|${CONTAINER_NAME}|" ${CONTAINER_PATH}/etc/hosts

  FINISH=$(date +%s)
  echo "Customizing ${CONTAINER_NAME} took $(($FINISH-$START)) seconds."

  START=$(date +%s)
  # Install the VM on this system.
  sudo virt-install \
    --autostart \
    --connect lxc:/// \
    --console pty,target_type=serial \
    --description "Unprivileged libvirt-LXC container created from ${LXC_TEMPLATE} on $(date)" \
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
lxc-destroy --force --name ${CONTAINER_BASE}

END=$(date +%s)
echo "$(basename $0) script completed in $(($END-$BEGIN)) seconds total."
