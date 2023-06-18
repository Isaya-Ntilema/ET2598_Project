#!/bin/bash

# Checking required arguments 
: ${1:?" Please specify the openrc, tag, and ssh_key"}
: ${2:?" Please specify the openrc, tag, and ssh_key"}
: ${3:?" Please specify the openrc, tag, and ssh_key"}

cd_time=$(date)
openrc_sr=${1}     # openrc file
tag_sr=${2}        # The tag for identifying resources
ssh_key_sr=${3}    # ssh_key
no_of_servers=$(grep -E '[0-9]' servers.conf) # Getting number of nodes from servers.conf

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


run_status=0 ##ansible run status
echo "Running operate mode for tag:$tag_sr using $openrc_sr for credentials"
source $openrc_sr

generate_config(){
    bastionfip=$(openstack server list --name $sr_bastion_server -c Networks -f value | grep -Po '\d+\.\d+\.\d+\.\d+' | awk 'NR==2')
    haproxyfip=$(openstack server list --name $sr_haproxy_server -c Networks -f value | grep -Po '\d+\.\d+\.\d+\.\d+' | awk 'NR==2')
    
    

    echo "$(date) Generating a config file"
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

    # generate hosts file
    echo "[bastion]" >> $hostsfile
    echo "$sr_bastion_server" >> $hostsfile
    echo " " >> $hostsfile
    echo "[haproxy]" >> $hostsfile
    echo "$sr_haproxy_server" >> $hostsfile
    
    echo " " >> $hostsfile
    echo "[webservers]" >> $hostsfile

    # Getting the list of running servers
    active_servers=$(openstack server list --status ACTIVE -f value -c Name | grep -oP "${tag_sr}"'_dev([1-9]+)')
    echo "$active_Servers"
    # Getting the IP address of all servers
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
}

delete_config(){
    if [[ -f "$hostsfile" ]] ; then
    rm "$hostsfile"
    fi
        
    if [[ -f "$sshconfig" ]] ; then
        rm "$sshconfig"
    fi
    
}

while true
do
    echo "$(date) $no_of_servers nodes are required as specified in servers.conf"

    existing_servers=$(openstack server list --status ACTIVE --column Name -f value)
    devservers_count=$(grep -c $sr_server <<< $existing_servers)
    echo "$(date) $devservers_count nodes available."
    
    total_servers=$(openstack server list --column Name -f value)
    total_count=$(grep -c $sr_server <<< $total_servers)

    if (($no_of_servers > $devservers_count)); then
        devservers_to_add=$(($no_of_servers - $devservers_count))
        echo "$(date) Creating $devservers_to_add more nodes ..."
        sequence=$(( $total_count+1 ))
        devserver_name=${sr_server}${sequence}

        run_status=1 ## ansible run status
        while [ $devservers_to_add -gt 0 ]
        do   
            server_create=$(openstack server create --image "Ubuntu 20.04 Focal Fossa 20200423"  $devserver_name --key-name "$sr_keypair" --flavor "2C-2GB" --network "$natverk_namn" --security-group "$sr_security_group")
            echo "$(date) Created $devserver_name node"
            ((devservers_to_add--))
            sequence=$(( $sequence+1 ))
            active=false
            while [ "$active" = false ]; do
                server_status=$(openstack server show "$devserver_name" -f value -c status)
                if [ "$server_status" == "ACTIVE" ]; then
                    active=true
                fi
            done
            devserver_name=${sr_server}${sequence}

        done

    elif (( $no_of_servers < $devservers_count )); then
        devservers_to_remove=$(($devservers_count - $no_of_servers))
        sequence1=0
        while [[ $sequence1 -lt $devservers_to_remove ]]; do
            server_to_delete=$(openstack server list --status ACTIVE -f value -c Name | grep -m1 -oP "${tag_sr}"'_dev([1-9]+)')     
            deleted_server=$(openstack server delete "$server_to_delete" --wait)
            echo "$(date) Removed $server_to_delete node"
            ((sequence1++))
        done
    else
        echo "$(date) Required number of nodes are available"
    fi
     
    current_servers=$(openstack server list --status ACTIVE --column Name -f value)
    new_count=$(grep -c $sr_server <<< $current_servers)

    
    if [[ "$no_of_servers" == "$new_count" &&  "$run_status" -eq 0 ]]
    then
        echo "$(date) Sleeping 30 seconds. Press CTRL-C if you want to exit. "    
    else
            delete_config
            generate_config
            echo "$(date) Running ansible playbook"
            ansible-playbook -i "$hostsfile" site.yaml
            run_status=0
            echo "$(date) Done, solution has been deployed."
    

    fi
     
    sleep 30
done
