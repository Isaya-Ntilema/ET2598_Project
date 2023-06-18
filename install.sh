#!/bin/bash

SECONDS=0 # Using this to find how much time the solution takes to deploy


# Checking if the required arguments are present - the openrc ${1}, the tag ${2} and the ssh_key ${3}
# The program will not run if these arguments are not present.
: ${1:?" Please specify the openrc, tag, and ssh_key"}
: ${2:?" Please specify the openrc, tag, and ssh_key"}
: ${3:?" Please specify the openrc, tag, and ssh_key"}


cd_time=$(date)
openrc_sr=${1}     # Fetching the openrc access file
tag_sr=${2}        # Fetching the tag for easy identification of items
ssh_key_sr=${3}    # Fetching the ssh_key for secure remote access
no_of_servers=$(grep -E '[0-9]' servers.conf) # Fetching the number of nodes from servers.conf


# Begin deployment by sourcing the given openrc file
echo "${cd_time} Starting deployment of $tag_sr using ${openrc_sr} for credentials."
source ${openrc_sr}


# Define variables
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


# Check for current keypairs

echo "$(date) Checking if we have ${sr_keypair} available."
current_keypairs=$(openstack keypair list -f value --column Name)
if echo "${current_keypairs}" | grep -qFx ${sr_keypair}
then
    echo "$(date) ${sr_keypair} already exists"
else    
    new_keypair=$(openstack keypair create --public-key ${ssh_key_sr} "$sr_keypair" )
    echo "$(date)  Adding ${sr_keypair} associated with ${ssh_key_sr}."
fi



# Checking current networks corresponding to the tag
current_networks=$(openstack network list --tag "${tag_sr}" --column Name -f value)
if echo "${current_networks}" | grep -qFx ${natverk_namn} 
then
    echo "$(date) ${natverk_namn} already exists"
else
    echo "$(date) Did not detect ${natverk_namn} in the OpenStack project, adding it."
    new_network=$(openstack network create --tag "${tag_sr}" "${natverk_namn}" -f json)
    echo "$(date) Added ${natverk_namn}."
fi



# Checking current subnets corresponding to the tag
current_subnets=$(openstack subnet list --tag "${tag_sr}" --column Name -f value)

if echo "${current_subnets}" | grep -qFx ${sr_subnet} 
then
    echo "$(date) ${sr_subnet} already exists"
else
    echo "$(date) Did not detect ${sr_subnet} in the OpenStack project, adding it."
    new_subnet=$(openstack subnet create --subnet-range 192.168.10.0/24 --allocation-pool start=192.168.10.2,end=192.168.10.30 --tag "${tag_sr}" --network "${natverk_namn}" "${sr_subnet}" -f json)
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
    echo "$(date) Adding networks to router."
    set_gateway=$(openstack router set --external-gateway ext-net ${sr_router})
    add_subnet=$(openstack router add subnet ${sr_router} ${sr_subnet})
    echo "$(date) Done."
fi



# Check current security groups
current_security_groups=$(openstack security group list --tag ${tag_sr} -f value)
if [[ -z "${current_security_groups}" ||  "${current_security_groups}" != *"${sr_security_group}"* ]]
then
    echo "$(date) Adding security group(s)."
    created_security_group=$(openstack security group create --tag ${tag_sr} ${sr_security_group} -f json)
    rule1=$(openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 22 --protocol tcp --ingress ${sr_security_group})
    rule2=$(openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 80 --protocol icmp --ingress ${sr_security_group})
    rule3=$(openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 5000 --protocol tcp --ingress ${sr_security_group})
    rule4=$(openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 8080 --protocol tcp --ingress ${sr_security_group})
    rule5=$(openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 6000 --protocol udp --ingress ${sr_security_group})
    rule6=$(openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 9090 --protocol tcp --ingress ${sr_security_group})
    rule7=$(openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 9100 --protocol tcp --ingress ${sr_security_group})
    rule8=$(openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 3000 --protocol tcp --ingress ${sr_security_group})
    rule9=$(openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 161 --protocol udp --ingress ${sr_security_group})
    rule10=$(openstack security group rule create --protocol 112 ${sr_security_group}) #VVRP protocol
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
            echo "$(date) Creating floating IP for the Bastion 1"
            created_fip1=$(openstack floating ip create ext-net -f json | jq -r '.floating_ip_address' > floating_ip1)
            fip1="$(cat floating_ip1)"
        fi
    else
            echo "$(date) Creating floating IP for the Bastion 2"
            created_fip1=$(openstack floating ip create ext-net -f json | jq -r '.floating_ip_address' > floating_ip1)
            fip1="$(cat floating_ip1)"
    fi
    echo "$(date) Did not detect ${sr_bastion_server}, launching it."
    bastion=$(openstack server create --image "Ubuntu 20.04 Focal Fossa 20200423" ${sr_bastion_server} --key-name ${sr_keypair} --flavor "1C-2GB" --network ${natverk_namn} --security-group ${sr_security_group}) 
    add_bastion_fip=$(openstack server add floating ip ${sr_bastion_server} ${fip1}) 
    echo "$(date) Floating IP assigned for bastion."
    echo "$(date) Added ${sr_bastion_server} server."
fi


if [[ "$existing_servers" == *"$sr_haproxy_server"* ]]; then
        echo "$(date) HAproxy already exists"
else 
    if [[ -n "$unassigned_ips" ]]; then
        fip2=$(echo "$unassigned_ips" | awk '{print $2}')
        if [[ -n "$fip2" ]]; then
            echo "$(date) 1 floating IP available for the HAproxy server."
        else
            echo " $(date) Creating floating IP for the HAproxy "
            created_fip2=$(openstack floating ip create ext-net -f json | jq -r '.floating_ip_address' > floating_ip2)
            fip2="$(cat floating_ip2)"
        fi
    else
            echo "$(date) Creating floating IP for HAproxy "
            created_fip2=$(openstack floating ip create ext-net -f json | jq -r '.floating_ip_address' > floating_ip2)
            fip2="$(cat floating_ip2)"
    fi
    echo "$(date) Did not detect ${sr_haproxy_server}, launching it."
    haproxy=$(openstack server create --image "Ubuntu 20.04 Focal Fossa 20200423" ${sr_haproxy_server} --key-name ${sr_keypair} --flavor "1C-2GB" --network ${natverk_namn} --security-group ${sr_security_group})
    add_haproxy_fip=$(openstack server add floating ip ${sr_haproxy_server} ${fip2})
    echo "$(date) Floating IP assigned for HAProxy."
    echo "$(date) Added ${sr_haproxy_server} server."
    
fi



devservers_count=$(grep -ocP ${sr_server} <<< ${existing_servers})


if((${no_of_servers} > ${devservers_count})); then
    devservers_to_add=$((${no_of_servers} - ${devservers_count}))
    sequence=$(( ${devservers_count}+1 ))
    devserver_name=${sr_server}${sequence}

    while [ ${devservers_to_add} -gt 0 ]  
    do    
        server_output=$(openstack server create --image "Ubuntu 20.04 Focal Fossa 20200423"  ${devserver_name} --key-name "${sr_keypair}" --flavor "1C-2GB" --network ${natverk_namn} --security-group ${sr_security_group})
        echo "$(date) Node ${devserver_name} created."
        ((devservers_to_add--))
        
        active=false
        while [ "$active" = false ]; do
            server_status=$(openstack server show "$devserver_name" -f value -c status)
            if [ "$server_status" == "ACTIVE" ]; then
                active=true
            fi
        done

        sequence=$(( $sequence+1 ))
        devserver_name=${sr_server}${sequence}

    done

elif (( $no_of_servers < $devservers_count )); then
    devservers_to_remove=$(($devservers_count - $no_of_servers))
    sequence1=0
    while [[ $sequence1 -lt $devservers_to_remove ]]; do
        server_to_delete=$(openstack server list --status ACTIVE -f value -c Name | grep -m1 -oP "${tag_sr}"'_dev([1-9]+)')   
        deleted_server=$(openstack server delete "$server_to_delete" --wait)
        echo " $(date) Deleted $server_to_delete server"
        ((sequence1++))
    done
else
    echo "Required number of servers($no_of_servers) already exist."
fi


bastionfip=$(openstack server list --name ${sr_bastion_server} -c Networks -f value | grep -Po '\d+\.\d+\.\d+\.\d+' | awk 'NR==2')
haproxyfip=$(openstack server list --name ${sr_haproxy_server} -c Networks -f value | grep -Po '\d+\.\d+\.\d+\.\d+' | awk 'NR==2')



echo "$(date) Generating config file"
echo "Host $sr_bastion_server" >> $sshconfig
echo "   User ubuntu" >> $sshconfig
echo "   HostName $bastionfip" >> $sshconfig
echo "   IdentityFile ~/.ssh/id_rsa" >> $sshconfig
echo "   UserKnownHostsFile /dev/null" >> $sshconfig
echo "   StrictHostKeyChecking no" >> $sshconfig
echo "   PasswordAuthentication no" >> $sshconfig

echo " " >> $sshconfig
echo "Host $sr_haproxy_server" >> $sshconfig
echo "   User ubuntu" >> $sshconfig
echo "   HostName $haproxyfip" >> $sshconfig
echo "   IdentityFile ~/.ssh/id_rsa" >> $sshconfig
echo "   StrictHostKeyChecking no" >> $sshconfig
echo "   PasswordAuthentication no ">> $sshconfig
echo "   ProxyJump $sr_bastion_server" >> $sshconfig

# Generating hosts file
echo "[bastion]" >> $hostsfile
echo "$sr_bastion_server" >> $hostsfile
echo " " >> $hostsfile
echo "[haproxy]" >> $hostsfile
echo "$sr_haproxy_server" >> $hostsfile

echo " " >> $hostsfile
echo "[webservers]" >> $hostsfile

# Get the list of active servers
active_servers=$(openstack server list --status ACTIVE -f value -c Name | grep -oP "$tag_sr"'_dev([1-9]+)')
echo "$active_Servers"
# Loop through each active server and extract its IP address
for server in $active_servers; do
        ip_address=$(openstack server list --name $server -c Networks -f value | grep -Po  '\d+\.\d+\.\d+\.\d+')
        echo " " >> $sshconfig
        echo "Host $server" >> $sshconfig
        echo "   User ubuntu" >> $sshconfig
        echo "   HostName $ip_address" >> $sshconfig
        echo "   IdentityFile ~/.ssh/id_rsa" >> $sshconfig
        echo "   UserKnownHostsFile=~/dev/null" >> $sshconfig
        echo "   StrictHostKeyChecking no" >> $sshconfig
        echo "   PasswordAuthentication no" >> $sshconfig
        echo "   ProxyJump $sr_bastion_server" >> $sshconfig 

        echo "$server" >> $hostsfile
done


echo " " >> $hostsfile
echo "[all:vars]" >> $hostsfile
echo "ansible_user=ubuntu" >> $hostsfile
echo "ansible_ssh_private_key_file=~/.ssh/id_rsa" >> $hostsfile
echo "ansible_ssh_common_args=' -F $sshconfig '" >> $hostsfile

echo "$(date) Running ansible playbook"
ansible-playbook -i "$hostsfile" site.yaml


echo "Bastion IP address: $fip1"
echo "HAproxy IP address: $fip2"

# Displaying time taken by the script to deploy the environment
duration=$SECONDS
echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."
