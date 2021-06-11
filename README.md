# Containers vs. VMs

A collection of scripts to manage a large number of very basic LXC containers
and VMs for testing or comparison.

## LXC?

Yeah, yeah we all know and use Docker containers, but some times you need a
init system. This is using the old LXC commands, because LXD does not exist
in Debian repositories (and we can't all use Ubuntu). The commands are pretty
limited in this version of LXC but was able to figure out a few things out that
were not well covered elsewhere.

### Too many open files

Creating a large number of containers can make the host Linux system to run out
of inotify instances, watchers and pseudo tty sessions. The signature of this
problem is being unable to start the container. Because the container's systemd
is reporting degraded state and the script can not complete.

To verify this problem attempt to start the container in the foreground and
observe the problem text:  

```
sudo lxc-start -F -n lxc168
...
Failed to create control group inotify object: Too many open files
Failed to allocate manager object: Too many open files
...
```

To see the specific watches and instance kernel limits print the contents of the
runtime files:  

```
cat /proc/sys/fs/inotify/max_user_watches
65536
cat /proc/sys/fs/inotify/max_user_instances
1024
```

To increase the inotify instances, watchers and pty by configuring the kernel
runtime parameters. You can do this by editing the `/etc/sysctl.conf` file or
write your own file to the `/etc/sysctl.d` directory.

```
echo fs.inotify.max_user_watches = 98304 | sudo tee -a /etc/sysctl.d/50-lxc-limit-increase.conf
echo fs.inotify.max_user_instances = 1536 | sudo tee -a /etc/sysctl.d/50-lxc-limit-increase.conf
echo kernel.pty.max = 6144 | sudo tee -a /etc/sysctl.d/50-lxc-limit-increase.conf
sudo sysctl --system
```

---

### LXC References

* [Linux Containers](https://www.ubuntupit.com/everything-you-need-to-know-about-linux-containers-lxc/)
* [Debian LXC](https://wiki.debian.org/LXC)
  * [LXC SimpleBridge](https://wiki.debian.org/LXC/SimpleBridge)
* [Linux Containers LXC](https://linuxcontainers.org/lxc/introduction/)
* [Exploring Containers LXC](https://www.redhat.com/sysadmin/exploring-containers-lxc)
* [Debian template](https://github.com/lxc/lxc-templates/blob/master/templates/lxc-debian.in)

---

## Virtual Machines

The libguestfs tools are awesome! The tools can be used to build and install a
KVM virtual machine very quickly. I spent some time learning how to use the
commands correctly, so wanted to commit the information to a repository for
reference in the future.

### Overcommitting memory

Each VM is configured with a maximum amount of memory when defined. Not all VMs
consume the full amount of memory all the time. Therefore it is possible to run
VMs with more RAM than what is available on the host. This is called
overcommitting memory.

See more details about
[overcommitting memory](https://docs.fedoraproject.org/en-US/Fedora/13/html/Virtualization_Guide/sect-Virtualization-Tips_and_tricks-Overcommitting_with_KVM.html)
and the way to do this correctly and safely.

### VM References

* [libguestfs website](https://www.libguestfs.org/)
  * [virt-builder](https://www.libguestfs.org/virt-builder.1.html)
    * [virt-builder how to](https://ostechnix.com/quickly-build-virtual-machine-images-with-virt-builder/)
  * [virt-resize](https://www.libguestfs.org/virt-resize.1.html)
  * [virt-sparsify](https://www.libguestfs.org/virt-sparsify.1.html)
  * [virt-install](https://unix.stackexchange.com/questions/207090/install-vm-from-command-line-with-virt-install)
* [Overcommitting KVM memory](https://docs.fedoraproject.org/en-US/Fedora/13/html/Virtualization_Guide/sect-Virtualization-Tips_and_tricks-Overcommitting_with_KVM.html)
---

The idea is to get a comparison between system containers and VMs without the
marketing bull.

---

## libvirt-LXC

The libvirt LXC driver manages linux containers. This is different than the
userspace LXC commands. The libvirt LXC containers would show up in
virt-manager application.

libvirt-LXC containers require a filesystems to be mounted.
You can create a libvirt LXC container with LXC commands or debootstrap
commands.

```
virsh --connect lxc:/// define newguest.xml
virsh --connect lxc:/// start newguest.xml
virsh --connect lxc:/// undefine newguest
virsh --connect lxc:/// destroy newguest

```

### libvirt-LXC References

* [libvirt-LXC](https://libvirt.org/drvlxc.html)

---

## debootstrap

debootstrap is a tool that installs a Debian system into a subdirectory of
another already installed system. It only requires access to a Debian
repository it can be run from other operating systems.

debootstrap can be run completely from a command line, no config files are
required.

```
debootstrap --include=sudo,vim-tiny stable /var/lib/machines/debian

````

---

## systemd-nspawn

systemd-nspawn may be used to run a command in a light-weight namespace
container similar to chroot but also virtualizes the filesystem hierarchy,
process tree, various IPC subsystems.

```
systemd-nspawn -D /var/lib/machines/debian -U --machine debian

systemctl start systemd-nspawn@debian

systemctl stop systemd-nspawn@debian

```

---

## machinectl

The command machine control can start and login to containers.

```
machinectl list
machinectl login debian

```

### References

* [debootstrap](https://wiki.debian.org/Debootstrap)
* [systemd-nspawn](https://wiki.debian.org/nspawn)
* [machinectl](https://www.freedesktop.org/software/systemd/man/machinectl.html)

---
