#!/usr/bin/env bash

# Delete a number of VMs from this system.

if [ "$#" -eq 2 ] ; then
  # When there are two arguments, the first is range start, the second is stop.
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
BEGIN=$(date +%s)
VM_PREFIX=vm

# Loop over the specified number of VMs.
for NUM in $(seq -w ${RANGE_START} ${RANGE_STOP}); do
  # Create the VM name based on number.
  VM_NAME=${VM_PREFIX}${NUM}
  # Stop the VM immediately.
  sudo virsh destroy ${VM_NAME}
  # Delete the VM and remove all the storage.
  sudo virsh undefine --remove-all-storage ${VM_NAME}
done

END=$(date +%s)
echo "$(basename $0) script completed in $(($END-$BEGIN)) seconds total."
