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
BEGIN=$(date +%s)

# Comma separated list of packages to install.
PACKAGES=python3-minimal,sudo
VM_BASE=debian-10
VM_DISK_SIZE=12G
VM_FORMAT=qcow2
VM_BASE_FILE=${VM_BASE}.${VM_FORMAT}
# The type and name of network to use for the virtual machines (bridge=br0).
VM_NETWORK="network=default"
VM_PREFIX=vm
VM_RAM=1024

BANNER_FILE=banner.txt

# Use the new Elliptic Curve Digital Signature Algorithm standarized by the US government.
ALGORITHM=ecdsa
PRIVATE_KEY=id_${ALGORITHM}
PUBLIC_KEY=id_${ALGORITHM}.pub
# Create a new ssh key to manage the VMs.
ssh-keygen -b 521 -t ${ALGORITHM} -P "" -C "${ALGORITHM} ssh key" -f ${PRIVATE_KEY}

# Prompt the user for the administrator password.
read -s -p "Enter administrator password for the VMs:" UNENCRYPTED_PASSWORD
# Create the encrypted password with mkpasswd --method=sha-512
ENCRYPTED_PASSWORD=$(mkpasswd --method=sha-512 ${UNENCRYPTED_PASSWORD})

# Ensure the VM guestfs tools are installed on the host.
sudo apt install libguestfs-tools

START=$(date +%s)

echo "Starting build of ${VM_BASE_FILE} at $(date)"
# Build a minimal install of a debian VM first before the loop starts.
virt-builder ${VM_BASE} \
  --format ${VM_FORMAT} \
  --append-line "/etc/network/interfaces:auto enp1s0" \
  --append-line "/etc/network/interfaces:iface enp1s0 inet dhcp" \
  --install ${PACKAGES} \
  --output ${VM_BASE_FILE} \
  --run-command 'useradd -c "Administrator account" -d ${ADMIN_HOME} -G sudo -m -s /bin/bash '"${ADMIN}"'' \
  --smp 4 \
  --ssh-inject ${ADMIN}:file:${PUBLIC_KEY} \
  --root-password password:${UNENCRYPTED_PASSWORD} \
  --password ${ADMIN}:password:${UNENCRYPTED_PASSWORD} \
  --size ${VM_DISK_SIZE} \
  --upload ${BANNER_FILE}:/etc/${BANNER_FILE} \
  --link /etc/${BANNER_FILE}:/etc/issue.net:/etc/issue \
  --run-command 'sed -i "s|^#Banner.*|Banner /etc/'"${BANNER_FILE}"'|" /etc/ssh/sshd_config' \
  --firstboot-command "dpkg-reconfigure openssh-server"
FINISH=$(date +%s)
echo "Building ${VM_BASE} took $(($FINISH-$START)) seconds."

# Loop in a sequence for the desired number of VMs.
for NUM in $(seq -w ${RANGE_START} ${RANGE_STOP}); do
  START=$(date +%s)

  VM_NAME=${VM_PREFIX}${NUM}
  DISK_PATH=${VM_NAME}.${VM_FORMAT}

  echo "Starting customization of ${VM_NAME} at $(date)"
  # Copy the VM base file to the disk path and set a different hostname.
  cp -v --sparse=always ${VM_BASE_FILE} ${DISK_PATH}
  # Set the hostname for this VM image.
  virt-customize -a ${DISK_PATH} \
    --hostname ${VM_NAME}

  FINISH=$(date +%s)
  echo "Customizing ${VM_NAME} took $(($FINISH-$START)) seconds."

  START=$(date +%s)
  # Install the VM on this system.
  sudo virt-install \
    --autostart \
    --console pty,target_type=serial \
    --cpu=host \
    --description "Virtual Machine created from ${VM_BASE} on $(date)" \
    --disk path=${DISK_PATH},format=${VM_FORMAT} \
    --import \
    --memory ${VM_RAM} \
    --name ${VM_NAME} \
    --network ${VM_NETWORK} \
    --noautoconsole \
    --os-type linux \
    --os-variant debian10 \
    --serial pty \
    --vcpus 2

  FINISH=$(date +%s)
  echo "Installing ${VM_NAME} took $(($FINISH-$START)) seconds."
done

# Delete the VM base file
rm ${VM_BASE_FILE}

END=$(date +%s)
echo "$(basename $0) script completed in $(($END-$BEGIN)) seconds total."
