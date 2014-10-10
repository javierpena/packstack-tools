#!/bin/bash

# Set the following configuration options according to your environment
TEMPLATE_VM=rhel7-base
VM_FOLDER=/home/jpena/VMs

# Change this variable if you want to test any specific Packstack option
PACKSTACK_DEFAULT_OPTIONS="--debug"

usage()
{
	echo "testpackstack_rhel7_4systems.sh <RHSM user> <RHSM passwd>"
}


clone_vm()
{
 UUID=$(openssl rand -hex 6)
 sudo virt-clone  -o ${TEMPLATE_VM} -n rhel7-${UUID} -f ${VM_FOLDER}/rhel7-${UUID}.qcow2
 if [ $? -ne 0 ]
 then
    echo "Error cloning $1 VM. Stopping"
    exit 3
 fi 
 return 0
}

start_vm()
{
 sudo virsh start rhel7-$1
 if [ $? -ne 0 ]
 then
    echo "Error starting $2 VM. Stopping"
    exit 4
 fi
}

get_vm_ip()
{
 VMMAC=""
 while [ "x$VMMAC" == "x" ]
 do
	VMMAC=$(sudo virsh dumpxml rhel7-$1 | grep "mac address" | awk -F\' '{print $2}')
 	if [ "x$VMMAC" == "x" ]
    then
		echo "MAC not found yet, sleeping..."
		sleep 5
	fi
 done

 VMIP=""
 while [ "x$VMIP" == "x" ]
 do
	VMIP=$(arp -an | grep $VMMAC | awk '{print $2}' | tr -d \( | tr -d \))
        if [ "x$VMIP" == "x" ]
        then
                echo "IP not found yet, sleeping..."
                sleep 5
        else
		echo "VM booted with IP " $VMIP
	fi
 done
}

rhnreg_vm()
{
 vmIP=$1

 SSHOK=0
 while [ ${SSHOK} -eq 0 ]
 do
    ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null root@${vmIP} ls /root > /dev/null
    if [ $? -eq 0 ]
    then
        SSHOK=1
    else
        echo "Cannot connect via SSH. Waiting"
        sleep 10
    fi
 done

 ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null root@${vmIP} "/bin/bash " << EOF
 echo ${2}.example.com > /etc/hostname
 subscription-manager register --username=${RHSMUSER} --password=${RHSMPASS} 
 subscription-manager attach --auto
 subscription-manager repos --disable \* 
 subscription-manager repos --enable rhel-7-server-rpms 
 subscription-manager repos --enable rhel-7-server-openstack-5.0-rpms 
 subscription-manager repos --enable rhel-7-server-rh-common-rpms 
 yum -y update ;
 reboot
EOF
}

is_vm_alive()
{
 count=0
 found=0
 while [ $count -lt 10 ]
 do
	ping -c 1 $1 > /dev/null
	if [ $? -eq 0 ]
	then
		found=1
		count=10
	else
		sleep 10
		((count=$count+1))
		echo $count
	fi
 done

 if [ $found -eq 0 ]
 then
    return $found
 fi

 SSHOK=0
 while [ ${SSHOK} -eq 0 ]
 do
    ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null root@$1 ls /root > /dev/null
    if [ $? -eq 0 ]
    then
        SSHOK=1
    else
        echo "Cannot connect via SSH. Waiting"
        sleep 10
    fi
 done

 return $SSHOK
}

generate_and_replicate_sshkeys()
{
 controllerIP=$1
 networkIP=$2
 compute1IP=$3
 compute2IP=$4

 ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null root@${controllerIP} << EOF
 mkdir /root/.ssh
 ssh-keygen -t dsa -f /root/.ssh/id_dsa -P ""
EOF

 scp -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null root@${controllerIP}:/root/.ssh/id_dsa.pub /tmp/id_dsa.pub
 pubkey=$(cat /tmp/id_dsa.pub)
 
 for ip in $controllerIP $networkIP $compute1IP $compute2IP
 do 
    ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null root@${ip} "echo $pubkey >> /root/.ssh/authorized_keys"
    ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null root@${ip} "chmod 600 /root/.ssh/authorized_keys"
 done
}


run_packstack()
{
 controllerIP=$1
 networkIP=$2
 compute1IP=$3
 compute2IP=$4

 PACKSTACK_OPTIONS="${PACKSTACK_DEFAULT_OPTIONS} --os-controller-host=${controllerIP} --os-network-hosts=${networkIP} --os-compute-hosts=${compute1IP},${compute2IP}"

 SSHOK=0
 while [ ${SSHOK} -eq 0 ]
 do
    ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null root@${controllerIP} ls /root > /dev/null
    if [ $? -eq 0 ]
    then
        SSHOK=1
    else
        echo "Cannot connect via SSH. Waiting"
        sleep 10
    fi
 done

 ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null root@${controllerIP} "/bin/bash" << EOF
 yum -y install openstack-packstack
 packstack --gen-answer-file=/root/aio-4node.txt
 sed --in-place 's/CONFIG_HEAT_INSTALL=n/CONFIG_HEAT_INSTALL=y/g' /root/aio-4node.txt
 sed --in-place "s/CONFIG_COMPUTE_HOSTS=${controllerIP}/CONFIG_COMPUTE_HOSTS=${compute1IP},${compute2IP}/" /root/aio-4node.txt
 sed --in-place "s/CONFIG_NETWORK_HOSTS=${controllerIP}/CONFIG_NETWORK_HOSTS=${networkIP}/" /root/aio-4node.txt
 sed --in-place "s/CONFIG_PROVISION_TEMPEST=n/CONFIG_PROVISION_TEMPEST=y/" /root/aio-4node.txt
 packstack ${PACKSTACK_DEFAULT_OPTIONS}--answer-file=/root/aio-4node.txt
EOF
}


# Main
if [ $# -ne 2 ]
then
	usage
	exit 2
fi

RHSMUSER=$1
RHSMPASS=$2

clone_vm controller
UUID1=$UUID
clone_vm network
UUID2=$UUID
clone_vm hypervisor1
UUID3=$UUID
clone_vm hypervisor2
UUID4=$UUID

start_vm $UUID1 controller
start_vm $UUID2 network
start_vm $UUID3 hypervisor1
start_vm $UUID4 hypervisor2

get_vm_ip $UUID1
VMIP1=$VMIP
get_vm_ip $UUID2
VMIP2=$VMIP
get_vm_ip $UUID3
VMIP3=$VMIP
get_vm_ip $UUID4
VMIP4=$VMIP

sleep 30 # Give some time for VMs to boot

rhnreg_vm $VMIP1 controller
rhnreg_vm $VMIP2 network
rhnreg_vm $VMIP3 hypervisor1
rhnreg_vm $VMIP4 hypervisor2

is_vm_alive $VMIP1
if [ $? -ne 1 ]
then
	echo "Controller VM did not reboot properly. Check, destroy and try again"
	exit 1
fi
is_vm_alive $VMIP2
if [ $? -ne 1 ]
then
	echo "Controller VM did not reboot properly. Check, destroy and try again"
	exit 1
fi
is_vm_alive $VMIP3
if [ $? -ne 1 ]
then
	echo "Hypervisor1 VM did not reboot properly. Check, destroy and try again"
	exit 1
fi
is_vm_alive $VMIP4
if [ $? -ne 1 ]
then
	echo "Hypervisor2 VM did not reboot properly. Check, destroy and try again"
	exit 1
fi

generate_and_replicate_sshkeys $VMIP1 $VMIP2 $VMIP3 $VMIP4
run_packstack $VMIP1 $VMIP2 $VMIP3 $VMIP4


echo "Finished. You can now check logs and see how it went. Connect with"
echo "ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null root@${VMIP1}"

