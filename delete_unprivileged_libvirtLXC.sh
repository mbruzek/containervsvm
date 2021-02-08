#!/usr/bin/env bash

# Delete a number of containers.

if [ "$#" -eq 2 ] ; then
  # When there are two arguments, the first is range start, the second is stop.
  RANGE_START=$1
  RANGE_STOP=$2
elif [ "$#" -eq 1 ] ; then
  # When there is only one argument it is the range stop, starting at 1.
  RANGE_START=1
  RANGE_STOP=$1
else
  # When there are no arguments, delete one.
  RANGE_START=1
  RANGE_STOP=1
fi
BEGIN=$(date +%s)
CONTAINER_PREFIX=unpriv-libvirtLXC

# Loop over the specified number of VMs.
for NUM in $(seq -w ${RANGE_START} ${RANGE_STOP}); do
  # Create the container name based on the number.
  CONTAINER_NAME=${CONTAINER_PREFIX}${NUM}
  echo "Attempting to stop ${CONTAINER_NAME}"
  virsh --connect lxc:/// destroy ${CONTAINER_NAME}
  echo "Removing definition of ${CONTAINER_NAME} from virt-manager"
  virsh --connect lxc:/// undefine ${CONTAINER_NAME}
  # Root must change ownership back before lxc-destroy is called.
  sudo chown -R ${USER}:${USER} ${HOME}/.local/share/lxc/${CONTAINER_NAME}
  echo "Deleting the LXC container ${CONTAINER_NAME}"
  lxc-destroy --force --name ${CONTAINER_NAME}
done

END=$(date +%s)
echo "$(basename $0) script completed in $(($END-$BEGIN)) seconds total."
