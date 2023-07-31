#!/bin/bash

SECONDS=0 # Keeping track of the time taken to deploy the solution
# Checking the presence of required arguments
: ${1:?" Please specify the openrc, tag, and ssh_key"}
: ${2:?" Please specify the openrc, tag, and ssh_key"}
: ${3:?" Please specify the openrc, tag, and ssh_key"}

cd_time=$(date)
openrc_sr=${1}     # openrc access file
tag_sr=${2}        # tag for identification of items
ssh_key_path=${3}  # the ssh_key
no_of_servers=$(grep -E '[0-9]' servers.conf) # number of nodes from servers.conf

# Sourcing the given openrc file
echo "${cd_time} Starting deployment of $tag_sr using ${openrc_sr} for credentials."
source ${openrc_sr}

# Defining variables
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
nodes_yaml="nodes.yaml"

# Checking availability of keypairs
echo "$(date) Checking if we have ${sr_keypair} available."
current_keypairs=$(openstack keypair list -f value --column Name)
if echo "${current_keypairs}" | grep -qFx ${sr_keypair}
then
    echo "$(date) ${sr_keypair} already exists"
else 
    echo "$(date) Did not detect ${sr_keypair} in the OpenStack project."
    echo "$(date) Adding ${sr_keypair} associated with ${ssh_key_path}."
    new_keypair=$(openstack keypair create --public-key "${ssh_key_path}" "${sr_keypair}" )
fi

# Checking current networks
current_networks=$(openstack network list --tag "${tag_sr}" --column Name -f value)
if echo "${current_networks}" | grep -qFx ${natverk_namn} 
then
    echo "$(date) ${natverk_namn} already exists"
else
    echo "$(date) Did not detect ${natverk_namn} in the OpenStack project, adding it."
    new_network=$(openstack network create --tag "${tag_sr}" "${natverk_namn}" -f json)
    echo "$(date) Added ${natverk_namn}."
fi

# Checking current subnets 
current_subnets=$(openstack subnet list --tag "${tag_sr}" --column Name -f value)

if echo "${current_subnets}" | grep -qFx ${sr_subnet} 
then
    echo "$(date) ${sr_subnet} already exists"
else
    echo "$(date) Did not detect ${sr_subnet} in the OpenStack project, adding it."
    new_subnet=$(openstack subnet create --subnet-range 10.10.0.0/27 --allocation-pool start=10.10.0.2,end=10.10.0.30 --tag "${tag_sr}" --network "${natverk_namn}" "${sr_subnet}" -f json)
    echo "$(date) Added ${sr_subnet}."
fi



# Checking current routers
current_routers=$(openstack router list --tag "${tag_sr}" --column Name -f value)
if echo "${current_routers}" | grep -qFx ${sr_router} 
then
    echo "$(date) ${sr_router} already exists"
else
    echo "$(date) Did not detect ${sr_router} in the OpenStack project, adding it."
    new_router=$(openstack router create --tag ${tag_sr} ${sr_router})
    echo "$(date) Added ${sr_router}."
    echo "$(date) Configuring router."
    add_subnet=$(openstack router add subnet ${sr_router} ${sr_subnet})
    set_gateway=$(openstack router set --external-gateway ext-net ${sr_router})
    echo "$(date) Done."
fi



# Check current security groups
current_security_groups=$(openstack security group list --tag ${tag_sr} -f value)
if [[ -z "${current_security_groups}" ||  "${current_security_groups}" != *"${sr_security_group}"* ]]
then
    echo "$(date) Adding security group(s)."
    created_security_group=$(openstack security group create --tag ${tag_sr} ${sr_security_group} -f json)
    rule1=$(openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 22 --protocol tcp --ingress ${sr_security_group})
    # rule2=$(openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 80 --protocol tcp --ingress ${sr_security_group})
    rule3=$(openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 5000 --protocol tcp --ingress ${sr_security_group})
    rule4=$(openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 6000 --protocol udp --ingress ${sr_security_group})
    rule5=$(openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 161 --protocol udp --ingress ${sr_security_group})
    rule6=$(openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 80 --protocol icmp --ingress ${sr_security_group})
    echo "$(date) Done."
else
    echo "$(date) ${sr_security_group} already exists"
fi


if [[ -f "$sshconfig" ]] ; then
    rm "$sshconfig"
fi

if [[ -f "$knownhosts" ]] ; then
    rm "$knownhosts"
fi

if [[ -f "$hostsfile" ]] ; then
    rm "$hostsfile"
fi

if [[ -f "$nodes_yaml" ]] ; then
    rm "$nodes_yaml"
fi



unassigned_ips=$(openstack floating ip list --status DOWN -f value -c "Floating IP Address")


# Node creation

existing_servers=$(openstack server list --status ACTIVE --column Name -f value)

if [[ "${existing_servers}" == *"${sr_bastion_server}"* ]]; then
        echo "$(date) ${sr_bastion_server} already exists"
else
   if [[ -n "${unassigned_ips}" ]]; then
        fip1=$(echo "${unassigned_ips}" | awk '{print $1}')
        if [[ -n "${fip1}" ]]; then
            echo "$(date) 1 floating IP available for the Bastion."
        else
            echo "$(date) Creating floating IP for the Bastion "
            created_fip1=$(openstack floating ip create ext-net -f json | jq -r '.floating_ip_address' > floating_ip1)
            fip1="$(cat floating_ip1)"
        fi
    else
            echo "$(date) Creating floating IP for the Bastion "
            created_fip1=$(openstack floating ip create ext-net -f json | jq -r '.floating_ip_address' > floating_ip1)
            fip1="$(cat floating_ip1)"
    fi
    echo "$(date) Did not detect ${sr_bastion_server}, launching it."
    bastion=$(openstack server create --image "Ubuntu 20.04 Focal Fossa x86_64" ${sr_bastion_server} --key-name ${sr_keypair} --flavor "1C-2GB-50GB" --network ${natverk_namn} --security-group ${sr_security_group}) 
    add_bastion_fip=$(openstack server add floating ip ${sr_bastion_server} ${fip1}) 
    echo "$(date) Floating IP assigned for bastion."
    echo "$(date) Added ${sr_bastion_server} server."
fi


if [[ "$existing_servers" == *"$sr_haproxy_server"* ]]; then
        echo "$(date) ${sr_haproxy_server} already exists"
else 
    if [[ -n "$unassigned_ips" ]]; then
        fip2=$(echo "$unassigned_ips" | awk '{print $2}')
        if [[ -n "$fip2" ]]; then
            echo "$(date) 1 floating IP available for the Proxy server."
        else
            echo "$(date) Creating floating IP for the Proxy "
            created_fip2=$(openstack floating ip create ext-net -f json | jq -r '.floating_ip_address' > floating_ip2)
            fip2="$(cat floating_ip2)"
        fi
    else
            echo "$(date) Creating floating IP for Proxy "
            created_fip2=$(openstack floating ip create ext-net -f json | jq -r '.floating_ip_address' > floating_ip2)
            fip2="$(cat floating_ip2)"
    fi
    echo "$(date) Did not detect ${sr_haproxy_server}, launching it."
    haproxy=$(openstack server create --image "Ubuntu 20.04 Focal Fossa x86_64" ${sr_haproxy_server} --key-name ${sr_keypair} --flavor "1C-2GB-50GB" --network ${natverk_namn} --security-group ${sr_security_group})
    add_haproxy_fip=$(openstack server add floating ip ${sr_haproxy_server} ${fip2})
    echo "$(date) Floating IP assigned for Proxy."
    echo "$(date) Added ${sr_haproxy_server} server."
    
fi



devservers_count=$(grep -ocP ${sr_server} <<< ${existing_servers})


if((${no_of_servers} > ${devservers_count})); then
    
    devservers_to_add=$((${no_of_servers} - ${devservers_count}))
    v=$[ $RANDOM % 40 + 10 ]
    devserver_name=${sr_server}${v}
    servernames=$(openstack server list --status ACTIVE -f value -c Name)
    
    # Checking for existence of nodes - also avoids name clashes
    check_name=0
    until [[ check_name -eq 1 ]]
    do  
        if echo "${servernames}" | grep -qFx ${devserver_name} 
        then
        v=$[ $RANDOM % 40 + 10 ]
        devserver_name=${sr_server}${v}
        else
        check_name=1     
        fi
    done
    
    echo "$(date) Creating the required number of nodes - $no_of_servers."
    while [ ${devservers_to_add} -gt 0 ]  
    do    
        server_output=$(openstack server create --image "Ubuntu 20.04 Focal Fossa x86_64"  ${devserver_name} --key-name "${sr_keypair}" --flavor "1C-2GB-50GB" --network ${natverk_namn} --security-group ${sr_security_group})
        echo "$(date) Node ${devserver_name} created."
        ((devservers_to_add--))
        
        active=false
        while [ "$active" = false ]; do
            server_status=$(openstack server show "$devserver_name" -f value -c status)
            if [ "$server_status" == "ACTIVE" ]; then
                active=true
            fi
        done
        
        servernames=$(openstack server list --status ACTIVE -f value -c Name)
        v=$[ $RANDOM % 40 + 10 ]
        devserver_name=${sr_server}${v}
        
        check_name=0
        
        until [[ check_name -eq 1 ]]
        do  
        if echo "${servernames}" | grep -qFx ${devserver_name} 
        then
        v=$[ $RANDOM % 40 + 10 ]
        devserver_name=${sr_server}${v} 
        else
        check_name=1     
        fi
        done
    
    

    done
    

elif (( $no_of_servers < $devservers_count )); then
    echo "$(date) There are more number of nodes present than required ($no_of_servers)."
    echo "$(date) Removing the additional nodes."
    devservers_to_remove=$(($devservers_count - $no_of_servers))
    sequence1=0
    while [[ $sequence1 -lt $devservers_to_remove ]]; do
        server_to_delete=$(openstack server list --status ACTIVE -f value -c Name | grep -m1 -oP "${tag_sr}"'_dev([0-9]+)')   
        deleted_server=$(openstack server delete "$server_to_delete" --wait)
        echo " $(date) Deleted $server_to_delete server"
        ((sequence1++))
    done
else
    echo "$(date) Required number of servers ($no_of_servers) already exist."
fi


bastionfip=$(openstack server list --name ${sr_bastion_server} -c Networks -f value | grep -Po '\d+\.\d+\.\d+\.\d+' | awk 'NR==2')
haproxyfip=$(openstack server list --name ${sr_haproxy_server} -c Networks -f value | grep -Po '\d+\.\d+\.\d+\.\d+' | awk 'NR==2')


ssh_key_sr=${ssh_key_path::-4} # Removing .pub from the ssh key path
 
 
echo "$(date) Generating config file"
echo "Host $sr_bastion_server" >> $sshconfig
echo "   User ubuntu" >> $sshconfig
echo "   HostName $bastionfip" >> $sshconfig
echo "   IdentityFile $ssh_key_sr" >> $sshconfig
echo "   UserKnownHostsFile /dev/null" >> $sshconfig
echo "   StrictHostKeyChecking no" >> $sshconfig
echo "   PasswordAuthentication no" >> $sshconfig

echo " " >> $sshconfig
echo "Host $sr_haproxy_server" >> $sshconfig
echo "   User ubuntu" >> $sshconfig
echo "   HostName $haproxyfip" >> $sshconfig
echo "   IdentityFile $ssh_key_sr" >> $sshconfig
echo "   StrictHostKeyChecking no" >> $sshconfig
echo "   PasswordAuthentication no ">> $sshconfig
echo "   ProxyJump $sr_bastion_server" >> $sshconfig

# Generating hosts file
echo "[bastion]" >> $hostsfile
echo "$sr_bastion_server" >> $hostsfile
echo " " >> $hostsfile
echo "[proxy]" >> $hostsfile
echo "$sr_haproxy_server" >> $hostsfile

echo " " >> $hostsfile
echo "[webservers]" >> $hostsfile


# Get the list of active servers
active_servers=$(openstack server list --status ACTIVE -f value -c Name | grep -oP "$tag_sr"'_dev([0-9]+)')
echo "$active_Servers"
# Loop through each active server and extract its IP address
for server in $active_servers; do
        ip_address=$(openstack server list --name $server -c Networks -f value | grep -Po  '\d+\.\d+\.\d+\.\d+')
        echo " " >> $sshconfig
        echo "Host $server" >> $sshconfig
        echo "   User ubuntu" >> $sshconfig
        echo "   HostName $ip_address" >> $sshconfig
        echo "   IdentityFile $ssh_key_sr" >> $sshconfig
        echo "   UserKnownHostsFile=~/dev/null" >> $sshconfig
        echo "   StrictHostKeyChecking no" >> $sshconfig
        echo "   PasswordAuthentication no" >> $sshconfig
        echo "   ProxyJump $sr_bastion_server" >> $sshconfig 

        echo "$server" >> $hostsfile

        echo "$ip_address" >> $nodes_yaml

done



echo " " >> $hostsfile
echo "[all:vars]" >> $hostsfile
echo "ansible_user=ubuntu" >> $hostsfile
echo "ansible_ssh_private_key_file=$ssh_key_sr" >> $hostsfile
echo "ansible_ssh_common_args=' -F $sshconfig '" >> $hostsfile

echo "$(date) Running ansible playbook"
ansible-playbook -i "$hostsfile" site.yaml
sleep 5
echo "$(date) Checking node availability through ${sr_bastion_server}."
curl "http://$bastionfip:5000"
echo "$(date) Deployment done."
echo "Bastion IP address: $bastionfip"
echo "Proxy IP address: $haproxyfip"

# Displaying time taken by the script to deploy the environment
duration=$SECONDS
echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."
