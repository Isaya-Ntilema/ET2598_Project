#!/bin/bash

# Checking required arguments
: ${1:?" Please specify the openrc, tag, and ssh_key"}
: ${2:?" Please specify the openrc, tag, and ssh_key"}
: ${3:?" Please specify the openrc, tag, and ssh_key"}

cd_time=$(date)
openrc_sr=${1}     # The openrc file
tag_sr=${2}        # The tag for identifying resources
ssh_key_sr=${3}    # The ssh_key
no_of_servers=$(grep -E '[0-9]' servers.conf) # number of nodes from servers.conf

# Sourcing openrc file
echo "$cd_time Cleaning up $tag_sr using $openrc_sr"
source $openrc_sr

# Variables
natverk_namn="${2}_network"
sr_subnet="${2}_subnet"
sr_keypair="${2}_key"
sr_router="${2}_router"
sr_security_group="${2}_security_group"
sr_haproxy_server="${2}_proxy"
sr_bastion_server="${2}_bastion"
sr_server="${2}_dev"

sshconfig="config"
knownhosts="known_hosts"
hostsfile="hosts"
fip2="$(cat floating_ip2)"

# Retrieving the list of servers with the tag
servers=$(openstack server list --name "$tag_sr" -c ID -f value)
n=$(echo "$servers" | wc -l)
# Deleting each server
if [ -n "$servers" ]; then
  echo "$(date) $n nodes, to be deleted"
  for server_id in $servers; do
    openstack server delete $server_id
  done
  echo "$(date) $n nodes have been deleted"
else
  echo "$(date) No nodes to delete"
fi

# Deleting the keypair
keypairs=$(openstack keypair list -f value -c Name | grep "$tag_sr*")

if [ -n "$keypairs" ]; then
  for key in $keypairs; do  
    openstack keypair delete $key
  done
  echo "$(date) Deleting $sr_keypair key"
else
  echo "$(date) No keypair to delete."
fi

floating_ip=$(openstack floating ip list --status DOWN -f value -c "Floating IP Address")

if [ -n "$floating_ip" ]; then
  for fip in $floating_ip; do
    openstack floating ip delete "$fip"
  done
  echo "$(date) Deleting all floating IPs"
else
  echo "$(date) No floating IPs to delete"
fi

subnet_id=$(openstack subnet list --tag "${tag_sr}" -c ID -f value)
if [ -n "${subnet_id}" ]; then
  for sub in ${subnet_id}; do
    openstack router remove subnet "${sr_router}" "$sub"
    openstack subnet delete "$sub"
  done
  echo "$(date) Delete ${sr_subnet} subnet"
else
  echo "$(date) No subnets to delete"
fi

# Removing the router
routers=$(openstack router list --tag ${tag_sr} -f value -c Name)
if [ -n "$routers" ]; then
  for r in $routers; do
    openstack router delete "$r"
  done
  echo "$(date) Deleting ${sr_router} router" 
else
  echo "$(date) No routers to delete"
fi

# Removing the network
networks=$(openstack network list --tag ${tag_sr} -f value -c Name)
if [ -n "$networks" ]; then
  for net in $networks; do
    openstack network delete "$net"
  done
  echo "$(date) Deleting ${network_name} network"
else
  echo "$(date) No networks to delete"
fi

# Removing security group rules
security_group=$(openstack security group list --tag $tag_sr -f value -c Name)
if [ -n "$security_group" ]; then
  for sec in $security_group; do
    openstack security group delete "$sec"
  done
  echo "$(date) Deleting ${sr_security_group} security group"
else
  echo "$(date) No security groups to delete"
fi

if [[ -f "$sshconfig" ]] ; then
    rm "$sshconfig"
fi

if [[ -f "$knownhosts" ]] ; then
    rm "$knownhosts"
fi

if [[ -f "floating_ip1" ]] ; then
    rm "floating_ip1"
fi

if [[ -f "floating_ip2" ]] ; then
    rm "floating_ip2"
fi

if [[ -f "$hostsfile" ]] ; then
    rm "$hostsfile"
fi
