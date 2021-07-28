#!/usr/bin/env bash

# Create a number of VMs using the libguestfs tools virt-builder virt-install.

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
# Use the new Elliptic Curve Digital Signature Algorithm standarized by the US government.
ALGORITHM=ecdsa
BEGIN=$(date +%s)
BANNER_FILE=banner.txt
HOST_PACKAGES="libguestfs-tools whois"
PRIVATE_KEY=id_${ALGORITHM}
PUBLIC_KEY=id_${ALGORITHM}.pub
VM_CPUS=2
VM_DISK_SIZE=12G
VM_FORMAT=qcow2
VM_IMAGES_DIRECTORY=/var/lib/libvirt/images
# The type and name of network to use for the virtual machines (bridge=br0).
VM_NETWORK="network=default"
# The VM network interface card is different from hypervisor to hypervisor.
VM_NIC=enp1s0
# Use `virt-builder --list` to get the list of supported os_versions
VM_OS_VERSION=debian-10
# Comma separated list of packages to install on the guest.
VM_PACKAGES=gpm,python3-apt,python3-minimal,qemu-guest-agent,sudo,vim-tiny
VM_PREFIX=kvm
VM_RAM=1024

# Create a new ssh key to manage the VMs.
ssh-keygen -b 521 -t ${ALGORITHM} -P "" -C "${ALGORITHM} ssh key" -f ${PRIVATE_KEY}

# Ensure the VM guestfs tools and mkpasswd (whois) are installed on the host.
sudo apt install -y ${HOST_PACKAGES}

# Prompt the user for the administrator password.
read -s -p "Enter the password for the VMs:" UNENCRYPTED_PASSWORD
# Create an encrypted password with mkpasswd --method=sha-512
ENCRYPTED_PASSWORD=$(mkpasswd --method=sha-512 ${UNENCRYPTED_PASSWORD})

START=$(date +%s)

echo "Starting build of ${VM_OS_VERSION} at $(date)"
# Build a minimal install of a debian VM before the loop starts.
sudo virt-builder ${VM_OS_VERSION} \
  --format ${VM_FORMAT} \
  --append-line "/etc/network/interfaces:auto ${VM_NIC}" \
  --append-line "/etc/network/interfaces:iface ${VM_NIC} inet dhcp" \
  --install ${VM_PACKAGES} \
  --output virt-builder_${VM_OS_VERSION}.${VM_FORMAT} \
  --run-command 'useradd -c "The Administrator account" -d '"${ADMIN_HOME}"' -G sudo -m -s /bin/bash '"${ADMIN}"'' \
  --smp 4 \
  --ssh-inject ${ADMIN}:file:${PUBLIC_KEY} \
  --root-password password:${UNENCRYPTED_PASSWORD} \
  --password ${ADMIN}:password:${UNENCRYPTED_PASSWORD} \
  --size ${VM_DISK_SIZE} \
  --upload ${BANNER_FILE}:/etc/issue \
  --link /etc/issue:/etc/issue.net \
  --run-command 'sed -i "s|^#Banner.*|Banner /etc/issue|" /etc/ssh/sshd_config' \
  --firstboot-command "dpkg-reconfigure openssh-server" \
  --write /etc/sudoers.d/50-${ADMIN}-NOPASSWD:"${ADMIN} ALL=(ALL:ALL) NOPASSWD:ALL"

VM_BASE_DISK=${VM_OS_VERSION}.${VM_FORMAT}
# Compress and sparsify the image to make a smaller base file.
sudo virt-sparsify --compress virt-builder_${VM_OS_VERSION}.${VM_FORMAT} ${VM_BASE_DISK}
# Remove the initial virt-builder VM disk.
sudo rm -v virt-builder_${VM_OS_VERSION}.${VM_FORMAT}

FINISH=$(date +%s)
echo "Building ${VM_OS_VERSION} took $(($FINISH-$START)) seconds."

# Loop in a sequence for the desired number of VMs.
for NUM in $(seq -w ${RANGE_START} ${RANGE_STOP}); do
  START=$(date +%s)

  VM_NAME=${VM_PREFIX}${NUM}
  # Create the path to the final VM disk image.
  DISK_PATH=${VM_LIBVIRT_IMAGES}/${VM_NAME}.${VM_FORMAT}

  echo "Starting customization of ${VM_NAME} at $(date)"
  # Copy the VM base file to the final VM disk path.
  sudo cp -v --sparse=always ${VM_BASE_DISK} ${DISK_PATH}
  # Change ownership of the final VM disk.
  sudo chown ${USER}:${USER} ${DISK_PATH}

  # Set the hostname for this VM image.
  sudo virt-customize -a ${DISK_PATH} \
    --hostname ${VM_NAME}

  FINISH=$(date +%s)
  echo "Customizing ${VM_NAME} took $(($FINISH-$START)) seconds."

  START=$(date +%s)
  # Install the VM on this system.
  sudo virt-install \
    --autostart \
    --console pty,target_type=serial \
    --cpu=host \
    --description "Virtual Machine created from ${VM_OS_VERSION} on $(date)" \
    --disk path=${DISK_PATH},format=${VM_FORMAT} \
    --import \
    --memory ${VM_RAM} \
    --name ${VM_NAME} \
    --network ${VM_NETWORK} \
    --noautoconsole \
    --os-type linux \
    --os-variant debiantesting \
    --serial pty \
    --vcpus ${VM_CPUS}

  FINISH=$(date +%s)
  echo "Installing ${VM_NAME} took $(($FINISH-$START)) seconds."
done

# Delete the VM base file.
sudo rm -v ${VM_BASE_DISK}

END=$(date +%s)
echo "$(basename $0) script completed in $(($END-$BEGIN)) seconds total."
