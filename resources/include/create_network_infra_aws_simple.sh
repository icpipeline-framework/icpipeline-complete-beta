#!/bin/bash

# a simplified version of the aws network infra builder, which just creates:
# ICPipeline VPC with a single public subnet which will host the Fargate (only) cluster
# where our publicly-addressed Worker Dockers will live.

# This module handles network scaffolding in AWS for the ICPipeline framework installer.
# This runs either freestanding (in which case it's basically a generic VPC/subnet(s) builder),
# or as an include of the main installer.

echo
echo -e "${cyan}******************************************************************************${clear}"
echo
echo "This is the simplified ICPipeline AWS Network Module.  It creates an ICPipeline VPC in your account."
echo "Your ICPipeline VPC will be a public network with a single public subnet."
echo "Your ICPipeline Workers will have public IP addresses, reachable (SSH and browser) from anywhere."
echo
echo -e "${cyan}******************************************************************************${clear}"
echo

sleep 3

# Process/normalize received input args, which will vary by use case.  In regular use all passing args/vars script<>script
# is in the code.  Runtime should never require anything after the filename in question.
process_args "${@}"

# setting this hard to public network mode.
# NOTE for private network mode, use the main installer rather than hacking this one,
# this workflow is basically hard-coded for maximum simplicity.
public_network_mode=true
# name tag vars should be tweakable to suit without breakage.
# just observe AWS conventions, restrictions etc, because we're not valididating for that.
# name tagging will save headaches in busy/cluttered aws consoles.

# Internal cidr block for the whole VPC
vpc_cidr_internal="10.100.0.0/16"
# Internal range for the public subnet (this block being its private range, which it also has)
public_subnet_cidr_internal="10.100.0.0/24"
# Internal range for the private subnet (used only in Private Network Mode)
# private_subnet_cidr_internal="10.100.1.0/24"

# You can leave these as-is or name your resources to suit.
# Please note that we do not validate these, so it's on you to mind AWS conventions, char sets and other limits.
vpc_name_tag="ICPipeline VPC"
# Name the public subnet
public_subnet_name_tag="ICPipeline Public Subnet"
# Name the private subnet (used in Private Network Mode only)
# private_subnet_name_tag="ICPipeline Private Subnet"
# Name the Internet Gateway (VPC ingress/egress, both modes)
internet_gateway_name_tag="ICPipeline Internet Gateway"
# Name the public subnet route table
public_subnet_route_table_name_tag="ICPipeline Public Subnet Route Table"
# Name the private subnet route table (Public Network Mode only)
# private_subnet_route_table_name_tag="ICPipeline Private Subnet Route Table"
# This is the security group (local software firewall) applied to each individual Worker 
worker_security_group_name_tag="ICPipeline Worker Security Group"
# Name the NAT Gateway (Private Network Mode only)
# nat_gateway_name_tag="ICPipeline NAT Gateway"

# This custom ingress CIDR option is Public Network Mode only at the moment.
# Let us know if you think it should be available in both modes.  We opted for less clutter in the installer workflow,
# but there are Private-mode use cases where it would fit.  Ping and let us know what you think.
# User may submit (inline during execution) CIDR notation for an ingress address or class.  If a CIDR block is (optionally) entered,
# remote Worker access is restricted to source addresses in that range.
# General FYI: CIDR notation for any single IP address comprises the full address followed by "/32" eg. 123.123.123.123/32
# This works really well for solo devs and/or teams working in the same NAT'd private network.
# Default is wildcard (again, no need to change this here, option comes inline during install)
ingress_cidr_block="0.0.0.0/0"

# For outbound routes -- used in building route tables
egress_cidr_block="0.0.0.0/0"

# Controls for sizing Worker container resources (which directly affect the AWS bills).
# This is BY FAR the prevailing factor in framework TCO (see documention for more detail).
# CPU is in "CPU units".  1024 such units = 1 "vCPU"
# Memory is in bytes, i.e. 1024 = 1GB RAM.
# Note that a RAM/CPU ratio applies globally (per AWS), e.g. 1 vCPU will work with 2-8GB RAM.
# This same "between 2x and 8x" ratio holds up/down the overall sizing ladder.
# Also note that AWS data throughput rates work similarly here as with EC2, i.e. the pipe automatically grows fatter as you size up.
# These get cooked into the ECS task definition down below.
per_worker_cpu_units="2048"
per_worker_ram_bytes="4096"

# Certain items are declared locally if this module runs standalone, but inherited when this is invoked by the installer as an include.
# So basically, this is all stuff the installer takes care of an passes along.  But when running standalone, we need to take care of it here instead.
# (installer passes "include" as an argument to this module, hence the following IF).

installed_network_mode=$(echo "${installed_network_mode}" | tr 'A-Z' 'a-z')

# drop a line into worker conf for referral on the other end
# hardcoded for the moment for simple install 
echo -n "NETWORK_MODE=public" | xargs >> "${dotenv_file}"
#echo -n "NETWORK_MODE=private" | xargs >> "${dotenv_file}"

launch_mode_selection=fargate
# In all cases we capture the user's selected cluster type (Fargate vs EC2) to the resetter breadcrumb trail.
echo "INSTALLER_ECS_CLUSTER_TYPE=${launch_mode_selection}" >> "${resources_dir}"/util/installation_vars.env

echo
echo "Simplified install configures your Workers to accept inbound connections from all source IP addresses."
echo
echo "The number of Workers is defined by a variable in header of this script.  It's set to 2"
echo "by default, and you can change it (the number_of_workers variable) if you like."
echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

echo "Thank you."
echo
echo -e "Installer creates an SSH key pair for login into your ${cyan}ICPipeline Workers${clear}."
echo
echo -e "The private key is currently placed here: ${green}/resources/worker-ssh-key/${worker_ssh_keyfile_name}${clear}"
echo
echo "Please confirm that we should copy that private keyfile to your local home folder (~/.ssh )."
echo
echo "While the key itself will work from its present location, your Pipeline Manager dapp has connect buttons etc."
echo "that will work better if it's in your home folder."
echo
echo -e "Either way, it's a private key that should be handled accordingly."
echo
echo "************************************************************************************************"
echo

read -p "Copy Worker SSH key into your home directory? (<ENTER> to copy, or type \"NO\" to skip): " copy_ssh_key
copy_ssh_key=${copy_ssh_key:-'YES'} && copy_ssh_key=$(echo "${copy_ssh_key}" | tr 'A-Z' 'a-z')

if [[ "yes" == "${copy_ssh_key}" ]]
then
  
  cp -f ${resources_dir}/worker-ssh-key/${worker_ssh_keyfile_name} ~/.ssh/${worker_ssh_keyfile_name} && chmod 0400 ~/.ssh/${worker_ssh_keyfile_name}

  echo
  if [[ -f ~/.ssh/${worker_ssh_keyfile_name} ]]
  then
    echo -e "${green}Worker SSH key successfully copied to ~/.ssh/${worker_ssh_keyfile_name}${clear}"
    echo "with normal permissions for a private key file (0400)."
  else
    echo "Installer was unable to copy Worker SSH key."
    echo "Perhaps something relating to permissions and your shell setup...?"
    echo "Anyway, not a problem.  Just copy the key file manually, or use it from its present location (${resources_dir}/worker-ssh-key/${worker_ssh_keyfile_name})."
  fi
  echo
fi

echo
echo "Thanks for your input."
echo
echo -e "Your containerized ${cyan}ICPipeline Workers${clear} will have public IP addresses,"
echo "and they'll be hosted on AWS Fargate."
echo
echo "Installation will now proceed."
echo

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

echo "Starting infrastructure build in AWS..."

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

echo "Simplified install will set up a VPC with public subnet to host Worker containers..."

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

# ***********************************
# create and configure ICPipeline VPC
# ***********************************

# create vpc, fetch api response into local var
echo "Creating new VPC in selected AWS region ${aws_region} ..."
create_vpc_output=$(aws ec2 create-vpc --cidr-block "$vpc_cidr_internal" --output json)
echo "Output from create VPC:" >> "${aws_build_log}"
echo "${create_vpc_output}" >> "${aws_build_log}"

# fetch vpc id from api response into var
echo "Extracting VPC ID ..."
vpc_id=$(echo -e "$create_vpc_output" | jq '.Vpc.VpcId' | tr -d '"')

# assign name tag to vpc
echo "Tagging VPC as \"${vpc_name_tag}\"..."
sleep 3
aws ec2 create-tags --resources "$vpc_id" --tags Key=Name,Value="$vpc_name_tag"

# enable dns support on vpc
echo "Enabling DNS support on VPC ${vpc_id} ..."
enable_dns_support_output=$(aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-support "{\"Value\":true}")

# enable dns hostnames on vpc
echo "Enabling DNS hostnames on VPC ${vpc_id} ..."
enable_dns_hostnames_output=$(aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-hostnames "{\"Value\":true}")

# add delete vpc entry to aws resetter script (in reverse line order ... this one will execute last)
echo -e "\n" >> "${aws_resetter_script_reverse}"
echo "aws ec2 delete-vpc --vpc-id ${vpc_id} --output yaml-stream" >> "${aws_resetter_script_reverse}"
echo "echo \"Deleting VPC ${vpc_id} ...\"" >> "${aws_resetter_script_reverse}"

# *****************************************************
# create and tag internet gateway, attach it to the VPC
# *****************************************************

# create internet gateway for the public subnet (+ egress for the private subnet if default secure mode)
echo "Creating Internet Gateway for public subnet ..."
create_internet_gateway_output=$(aws ec2 create-internet-gateway --output json)
echo "Output from create Internet Gateway:" >> "${aws_build_log}"
echo "${create_internet_gateway_output}" >> "${aws_build_log}"

# extract igw id from response
internet_gateway_id=$(echo -e "$create_internet_gateway_output" |  jq '.InternetGateway.InternetGatewayId' | tr -d '"')

# inducing brief pauses prior to tagging operations, hedging against a *one-time* corner case
# wherein aws blipped when trying to tag a resource that was still in-process of creating.
# (the only actual breakage was a missing tag)
sleep 3

# assign name tag to internet gateway
echo "Tagging Internet Gateway ${internet_gateway_id} as \"${internet_gateway_name_tag}\" ..."
aws ec2 create-tags --resources "$internet_gateway_id" --tags Key=Name,Value="$internet_gateway_name_tag"

# attach internet gateway to vpc
echo "Attaching Internet Gateway ${internet_gateway_id} to VPC ${vpc_id} ..."
attach_gateway_vpc_output=$(aws ec2 attach-internet-gateway --internet-gateway-id "$internet_gateway_id" --vpc-id "$vpc_id")

# add delete internet gateway entry to aws resetter script (delete before detach, same reason) 
echo -e "\n" >> "${aws_resetter_script_reverse}"
echo "aws ec2 delete-internet-gateway --internet-gateway-id ${internet_gateway_id} --output yaml-stream" >> "${aws_resetter_script_reverse}"
echo "echo \"Deleting internet gateway ${internet_gateway_id} ...\"" >> "${aws_resetter_script_reverse}"

# *****************************************************
# create/configure public in the VPC for simple install
# *****************************************************

# create public subnet in vpc
echo "Creating public subnet in VPC ${vpc_id} ..."
create_public_subnet_output=$(aws ec2 create-subnet --cidr-block "$public_subnet_cidr_internal" --availability-zone "$aws_availability_zone" --vpc-id "$vpc_id" --output json)
echo "Output from create public subnet:" >> "${aws_build_log}"
echo "${create_public_subnet_output}" >> "${aws_build_log}"

# extract public subnet id (using jq)
public_subnet_id=$(echo -e "$create_public_subnet_output" |  jq '.Subnet.SubnetId' | tr -d '"')

# add delete public subnet entry to aws resetter script
echo -e "\n" >> "${aws_resetter_script_reverse}"
echo "aws ec2 delete-subnet --subnet-id ${public_subnet_id} --output yaml-stream" >> "${aws_resetter_script_reverse}"
echo "echo \"Deleting public subnet ${public_subnet_id} ...\"" >> "${aws_resetter_script_reverse}"

# detachment of the internet gateway needs to come before delete public subnet, so it needs to be AFTER that here.
# (because this all runs in reverse order in the final resetter script)
# add detach internet gateway entry to aws resetter script
echo -e "\n" >> "${aws_resetter_script_reverse}"
echo "aws ec2 detach-internet-gateway --internet-gateway-id ${internet_gateway_id} --vpc-id ${vpc_id}" >> "${aws_resetter_script_reverse}"
echo "echo \"Detaching internet gateway ${internet_gateway_id} from VPC ${vpc_id}...\"" >> "${aws_resetter_script_reverse}"

# ref prior comment
sleep 3

# assign name tag to public subnet:
echo "Tagging public subnet ${public_subnet_id} as \"${public_subnet_name_tag}\" ..."
aws ec2 create-tags --resources "$public_subnet_id" --tags Key=Name,Value="$public_subnet_name_tag"

# enable public IPs on public subnet
echo "Enabling public IP address support on ${public_subnet_name_tag} ${public_subnet_id} ..."
enable_public_ip_output=$(aws ec2 modify-subnet-attribute --subnet-id "$public_subnet_id" --map-public-ip-on-launch)
  
# create security group for assignment to worker dockers
echo -e "Creating security group to be applied to ${cyan}Worker Dockers${clear} ..."
create_worker_security_group_output=$(aws ec2 create-security-group --group-name "$worker_security_group_name_tag" --description "Private: $worker_security_group_name_tag" --vpc-id "$vpc_id" --output json)
echo "Output from create security group for Worker Dockers:" >> "${aws_build_log}"
echo "${create_worker_security_group_output}" >> "${aws_build_log}"

# extract security group id from aws api response
worker_security_group_id=$(echo -e "$create_worker_security_group_output" | jq '.GroupId' | tr -d '"')

# ref prior comment
sleep 3

# assign name tag to security group
echo "Tagging security group for Worker Dockers ${worker_security_group_id} as \"${worker_security_group_name_tag}\" ..."
aws ec2 create-tags --resources "${worker_security_group_id}" --tags Key=Name,Value="${worker_security_group_name_tag}"

# add delete worker security group entry to aws resetter script
echo -e "\n" >> "${aws_resetter_script_reverse}"
echo "aws ec2 delete-security-group --group-id ${worker_security_group_id} --output yaml-stream" >> "${aws_resetter_script_reverse}"
echo "echo \"Deleting Worker security group ${worker_security_group_id} ...\"" >> "${aws_resetter_script_reverse}"

echo -e "\n" >> "${aws_resetter_script_reverse}"
echo "sleep 90" >> "${aws_resetter_script_reverse}"
echo "echo \"Pausing 90 seconds to allow for AWS dependencies latency ...\"" >> "${aws_resetter_script_reverse}"

echo -e "Configuring remote access to ${cyan}Workers${clear} ..."

for tcp_port in "${ingress_ports_unique[@]}"
do
  echo "Enabling remote Worker access on port ${tcp_port} ..."
  echo "Output from enable ingress to Workers on port ${tcp_port}:" >> "${aws_build_log}"
  aws ec2 authorize-security-group-ingress --group-id "${worker_security_group_id}" --protocol tcp --port "${tcp_port}" --cidr "${ingress_cidr_block}" --output json >> "${aws_build_log}"
done

# **********************************************************************
# simple install: handle route tables and routes for public subnet only.
# **********************************************************************

# create route table for public subnet
echo "Creating route table for ${public_subnet_name_tag} ${public_subnet_id} ..."
create_public_subnet_route_table_output=$(aws ec2 create-route-table --vpc-id "${vpc_id}" --output json)
echo "Output from create public subnet route table:" >> "${aws_build_log}"
echo "${create_public_subnet_route_table_output}" >> "${aws_build_log}"

# fetch public subnet route table id
public_subnet_route_table_id=$(echo -e "${create_public_subnet_route_table_output}" | jq '.RouteTable.RouteTableId' | tr -d '"')

# ref prior comment
sleep 3

# name tag public subnet route table
echo "Tagging public subnet route table ${public_subnet_route_table_id} as \"${public_subnet_route_table_name_tag}\" ..."
aws ec2 create-tags --resources "${public_subnet_route_table_id}" --tags Key=Name,Value="${public_subnet_route_table_name_tag}" --output json >> "${aws_build_log}"

# add delete public subnet route table entry to aws resetter script
echo -e "\n" >> "${aws_resetter_script_reverse}"
echo "aws ec2 delete-route-table --route-table-id ${public_subnet_route_table_id} --output yaml-stream" >> "${aws_resetter_script_reverse}"
echo "echo \"Deleting public subnet route table ${public_subnet_route_table_id} ...\"" >> "${aws_resetter_script_reverse}"

# add route to public subnet route table
echo "Configuring egress route via ${internet_gateway_name_tag} ${internet_gateway_id} for ${public_subnet_route_table_name_tag} ${public_subnet_route_table_id} ..."
add_public_subnet_route_output=$(aws ec2 create-route --route-table-id "${public_subnet_route_table_id}" --destination-cidr-block "${egress_cidr_block}" --gateway-id "${internet_gateway_id}")
echo "Output from add route to route table:" >> "${aws_build_log}"
echo "${add_public_subnet_route_output}" >> "${aws_build_log}"

# associate public subnet route table with public subnet
echo "Applying ${public_subnet_route_table_name_tag} to ${public_subnet_name_tag} ..."
apply_public_subnet_route_table_output=$(aws ec2 associate-route-table --subnet-id "${public_subnet_id}" --route-table-id "${public_subnet_route_table_id}")
echo "Output from apply route table to public subnet:" >> "${aws_build_log}"
echo "${apply_public_subnet_route_table_output}" >> "${aws_build_log}"

# fetch the association id for the route table to the public subnet
public_subnet_route_table_association_id=$(echo -e "${apply_public_subnet_route_table_output}" | jq '.AssociationId' | tr -d '"')

# add disassociate public subnet route table from public subnet entry to aws resetter script
echo -e "\n" >> "${aws_resetter_script_reverse}"
echo "aws ec2 disassociate-route-table --association-id ${public_subnet_route_table_association_id}" >> "${aws_resetter_script_reverse}"
echo "echo \"Disconnecting route table from public subnet, removing associationId ${public_subnet_route_table_association_id} ...\"" >> "${aws_resetter_script_reverse}"

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

echo "AWS networking setup complete, returning to main installer workflow ...  "

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

sleep 1