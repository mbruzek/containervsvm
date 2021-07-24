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
CONTAINER_PREFIX=priv-LXC

# Loop over the specified number of VMs.
for NUM in $(seq -w ${RANGE_START} ${RANGE_STOP}); do
  # Create the container name based on the number.
  CONTAINER_NAME=${CONTAINER_PREFIX}${NUM}
  echo "Attempting to stop ${CONTAINER_NAME}"
  # Stop the container immediately.
  sudo lxc-stop --name ${CONTAINER_NAME}
  # Delete the container.
  sudo lxc-destroy --name ${CONTAINER_NAME}
done

END=$(date +%s)
echo "$(basename $0) script completed in $(($END-$BEGIN)) seconds total."
