packstack-tools
===============

Some tools and scripts to play around with PackStack.

# testpackstack_rhel7_4systems.sh

This script is meant to create a 4-node RHEL-OSP installation using 4 VMs, all running on a KVM host. 

## Pre-installation requirements

A RHEL (or Fedora) system with KVM is required to host the virtual machines used in the environment. 8 GB of RAM will be consumed by the virtual machines, so you will probably want to have as much RAM available as possible.

The installation procedure will use a RHEL 7 virtual machine as a template. Create a virtual machine with the following parameters:

* Name: rhel7-base
* 1 virtual CPU
* 2 GB of RAM
* 30 GB virtual disk. Make sure you use qcow2 for the disk image, to speed up the clone process.
* 1 virtual NIC. You can use NAT for the virtual network, just make sure the virtual machine will be reachable from the KVM host.

Run a minimal RHEL 7 installation. After installing, do the following:

* Generate a SSH keypair on the KVM host, and add it to the virtual machine's /root/.ssh/authorized_keys file:
----
ssh-copy-id root@virtual-machine-ip
----
* Log on to the virtual machine, and remove the HWADDR option from /etc/sysconfig/network-scripts/ifcfg-eth0
* Power off the virtual machine

== Installation procedure

The installation procedure is automated by a shell script (reference to script here). First, you will need to edit the following variables to fit your environment:

* TEMPLATE_VM
* VM_FOLDER

It is also possible to change the default options for PackStack, if you want to skip certain components. To do so, edit the following variable:

* PACKSTACK_DEFAULT_OPTIONS

When finished, run the script as follows:

----
./testpackstack_rhel7_4systems.sh <RHSM user> <RHSM password>
----

+<RHSM user>+ and +<RHSM password>+ are a username and password used to register the hosts using +subscription-manager+.

The script will do the following:

* Clone and start 4 virtual machines, from the +rhel7-base+ template (or any other template name specified).
* Register all virtual machines using subscription-manager, and assign them to the required repositories.
* Generate an SSH keypair for root on the controller node, and distribute it to all nodes.
* Prepare a PackStack answer file and execute it.

At the end of the process, the 4-node RHEL-OSP environment will be ready to use.

# Fixes, patches, complaints...

All are welcome ;).

