#!/bin/bash

# This module handles network scaffolding in AWS for the ICPipeline framework installer.
# This runs either freestanding (in which case it's basically a generic VPC/subnet(s) builder),
# or as an include of the main installer.

echo
echo -e "${cyan}******************************************************************************${clear}"
echo
echo "Welcome to the ICPipeline AWS Network Module.  This module creates an ICPipeline VPC with subnet(s) in your account."
echo "Your ICPipeline VPC will be a public or a private network, according to which ICPipeline Network Mode you select."
echo
echo -e "${cyan}******************************************************************************${clear}"
echo

sleep 3

# Process/normalize received input args, which will vary by use case.  In regular use all passing args/vars script<>script
# is in the code.  Runtime should never require anything after the filename in question.
process_args "${@}"

# name tag vars should be tweakable to suit without breakage.
# just observe AWS conventions, restrictions etc, because we're not valididating for that.
# name tagging will save headaches in busy/cluttered aws consoles.

# We stand up an "ICPipeline VPC" in AWS, networking/addressing scheme vars pretty much right here in this header.
# FYI for those who want/need to tweak:
# Both subnet CIDR ranges must be non-colliding subsets of the VPC range -- if that bit's not obvious, perhaps leave as-is ;)
# We went with "10.100..." as opposed to 10.0..., for less likelihood of overlap with other private networks
# that might be in the stack for a given implementation.  While this is fully self-contained and sequestered,
# it doesn't hurt to be aware of the context you're dropping it into.
# There is also the (optional) inclusion of a VPN (similar VPN config vars live in the header of /resources/includes/create_vpn_aws.sh).
# There we use default 192.168... on the external/client side of the VPN (basically the dhcp pool handed out by the endpoint to connecting clients).
# If you use the VPN option (in Private Network Mode only), that VPN external block must not collide with your VPC's internal range.
# It works well as-is, and we recommend leaving it alone unless circumstances require otherwise.

# Internal cidr block for the whole VPC
vpc_cidr_internal="10.100.0.0/16"
# Internal range for the public subnet (this block being its private range, which it also has)
public_subnet_cidr_internal="10.100.0.0/24"
# Internal range for the private subnet (used only in Private Network Mode)
private_subnet_cidr_internal="10.100.1.0/24"

# You can leave these as-is or name your resources to suit.
# Please note that we do not validate these, so it's on you to mind AWS conventions, char sets and other limits.
vpc_name_tag="ICPipeline VPC"
# Name the public subnet
public_subnet_name_tag="ICPipeline Public Subnet"
# Name the private subnet (used in Private Network Mode only)
private_subnet_name_tag="ICPipeline Private Subnet"
# Name the Internet Gateway (VPC ingress/egress, both modes)
internet_gateway_name_tag="ICPipeline Internet Gateway"
# Name the public subnet route table
public_subnet_route_table_name_tag="ICPipeline Public Subnet Route Table"
# Name the private subnet route table (Public Network Mode only)
private_subnet_route_table_name_tag="ICPipeline Private Subnet Route Table"
# This is the security group (local software firewall) applied to each individual Worker 
worker_security_group_name_tag="ICPipeline Worker Security Group"
# Name the NAT Gateway (Private Network Mode only)
nat_gateway_name_tag="ICPipeline NAT Gateway"

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
if [[ ! true == ${include} ]]; then

  # should suppress pagination in AWS cli output if needed (avoiding potential need for intervention)
  export AWS_PAGER=""
  
  # fortunately this one doesn't require a ton of path referential stuff, but it does need a couple.
  project_home_dir="../.."
  resources_dir=${project_home_dir}/resources

  source ${resources_dir}/include/formatting.sh

  # Process/normalize received input args, which vary by use case (harmless if redundant in the odd corner case).
  process_args "${@}"

  # Set up to compile a takedown script that will basically undo everything this script does in AWS.
  # We'll compile the delete commands as we go, then basically play them back in reverse order -- last-in/first-out to avoid AWS dependency hell.
  # [note, the line-by-line writes mostly come from the AWS infra module script.]
  # Initialize the backwards version, to compile as we go
  aws_resetter_script_reverse="${resources_dir}/cloudconf/aws/aws_deletes_reverse_order.tmp"
  # Start both files clean in case remnants exist ... the whole point being multiple installer runs ...
  : > "${aws_resetter_script_reverse}"
  # Initiate the final product script ... this sits idle until we tac the backwards one into it at the end.
  aws_resetter_script="${resources_dir}/cloudconf/aws/reset_installation_aws.sh"
  : > "${aws_resetter_script}"
  # Add shebang and set the execute bit ...
  echo "#!/bin/bash" > "${aws_resetter_script}" && chmod +x "${aws_resetter_script}"

  # AWS profile particulars (inherited from the installer, or not).
  # fetch aws account id from user's aws profile, write it to .env file (using jq)
  aws_account_id=$(aws sts get-caller-identity | jq '.Account' | tr -d '"')
  # echo "AWS_ACCOUNT_ID=${aws_account_id}" | xargs >> "${dotenv_file}"
  echo "AWS_ACCOUNT_ID=${aws_account_id}"
  # likewise aws region
  aws_region=$(aws configure get region)
  # echo "AWS_REGION=${aws_region}" | xargs >> "${dotenv_file}"
  echo "AWS_REGION=${aws_region}"
  # ...and availability zone.
  # note that this returns the "first" availability zone (meaning @position[0] in the returned array from aws api)
  # in the user profile's designated region. (using jq)
  aws_availability_zone=$(aws ec2 describe-availability-zones --region ${aws_region} | jq '.AvailabilityZones[0].ZoneName' | tr -d '"')
  # echo "AWS_AVAILABILITY_ZONE=${aws_availability_zone}" | xargs >> "${dotenv_file}"
  echo "AWS_AVAILABILITY_ZONE=${aws_availability_zone}"

  # The more-secure Private Network Mode is the default (no need to change it here, installer UI presents the option).
  # This is mutually exclusive/boolean, a single true/false var would have covered the logic, did it this way for readability.
  private_network_mode=true && public_network_mode=false
  # just display, no logic attached.
  install_mode="Private Network Mode"

  # Initialize AWS build logfile
  aws_build_log="${resources_dir}"/installer-logs/aws.build.log
  touch "${aws_build_log}" || exit_on_err "Installer was unable to create file aws.build.log"

  # Validate user-input CIDR notation (cheers for the regex to Mark Hatton in UK)
  valid_cidr_regex='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(3[0-2]|[1-2][0-9]|[0-9]))$'

  # Validate user-input port numbers
  valid_port_regex='^([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$'

fi

# ***************************************************************************************************************************
# Handle user input selection of network architecture mode and sundry other important matters
# NOTE: In aid of a more rational/intuitive installer workflow, this script handles user inputs
# relating to a couple of significant items (the VPN option and Fargate vs EC2 container infra selection),
# and delivers the outcomes back to the main installer workflow, which hands off the actual work to their respective modules.
# ***************************************************************************************************************************

echo
echo -e "This is where you select the network architecture mode for this ${cyan}ICPipeline${clear} installation."
echo
echo -e "Choose either ${graylightbold}Private Network Mode${clear}, or ${graylightbold}Public Network Mode${clear}."
echo
echo -e "This selection defines the network environment -- public or private -- where your ${cyan}ICPipeline Workers${clear} will live."
echo
echo "Your choice will affect:"
echo -e "---> Remote (SSH) administrative access to your ${cyan}ICPipeline Workers${clear}."
echo -e "---> Browser accessibility to the projects that your ${cyan}Workers${clear} will build, deploy and (in some cases) host."
echo
echo -e "${cyan}******************************************************************************${clear}"
echo
echo -e "In ${graylightbold}Public Network Mode${clear}, ${cyan}ICPipeline Workers${clear} deploy into a public subnet, with public IP addresses."
echo 
echo -e "Your ${graylightbold}Public Network Mode${clear} implementation can still be secured.  You can enter an ingress IP address range in CIDR notation."
echo -e "By (optionally) entering a range, you'll limit remote access to your ${cyan}Workers${clear} to source addresses in that range."
echo
echo -e "${cyan}******************************************************************************${clear}"
echo
echo -e "In ${graylightbold}Private Network Mode${clear}, ${cyan}Workers${clear} deploy into a private subnet, having only private IP addresses."
echo
echo -e "Access to your ${graylightbold}Private Network Mode${clear} ${cyan}Workers${clear} can still be very convenient.  At your option, the installer"
echo "will create a VPN connecting directly into your private Worker network.  A bastion/jump host is also a viable option,"
echo "but we haven't automated that yet."
echo
echo -e "${cyan}******************************************************************************${clear}"
echo
echo "The README explains these options in greater detail, including the rationales behind our design choices.  If unsure which option"
echo "is best for you, please consult the README."
echo
echo -e "Enter \"PRIVATE\" (full word) for the recommended ${graylightbold}Private Network Mode${clear} installation."
echo
echo -e "This mode deploys your containerized ${cyan}Workers${clear} in a closed, private-network architecture."
echo
echo
echo -e "Enter \"PUBLIC\" (full word) for a ${graylightbold}Public Network Mode${clear} installation."
echo
echo -e "This mode deploys your ${cyan}Workers${clear} into a publicly addressed network."
echo

isgood=0
while [[ $isgood == 0 ]]; do

  echo
  read -p "Select a Worker network architecture (type and enter \"PUBLIC\" for Public Network Mode OR \"PRIVATE\" for Private Network Mode): " installed_network_mode
  installed_network_mode=${installed_network_mode:-'NA'} && installed_network_mode=$(echo "${installed_network_mode}" | tr 'A-Z' 'a-z')

  while [[ ! ${installed_network_mode} == "private" && ! ${installed_network_mode} == "public" ]]; do invalid_response; done
  if [[ ${installed_network_mode} == "private" ||  ${installed_network_mode} == "public" ]]; then isgood=1; fi

done

# Neutralize case for validation
installed_network_mode=$(echo "${installed_network_mode}" | tr 'A-Z' 'a-z')

if [[ "public" == "${installed_network_mode}" ]]
then

  public_network_mode=true && private_network_mode=false
  # just for display
  install_mode="Public Network Mode"
  # drop a line, one way or the other, into worker conf for referral on the other end
  echo -n "NETWORK_MODE=public" | xargs >> "${dotenv_file}"

else

  echo -n "NETWORK_MODE=private" | xargs >> "${dotenv_file}"

fi

if [[ "$private_network_mode" == true ]]
then

  echo
  echo -e "${cyan}******************************************************************************${clear}"
  echo
  echo -e "${graylightbold}Private Network Mode${clear} is a good choice.  And it's worth a moment to read this:"
  echo
  echo -e "Your ${cyan}ICPipeline Worker${clear} containers will be deployed in a private subnet, with only private IP addresses."
  echo
  echo -e "${graylight}Private Network Mode${clear} gives you two additional options that both provide more control over your"
  echo -e "containerized ${cyan}ICPipeline Workers${clear}."
  echo
  echo -e "${cyan}******************************************************************************${clear}"
  echo
  echo -e "First, an optional VPN provides a convenient way to connect to your ${cyan}Workers${clear} on their private addresses."
  echo
  echo -e "Second, ${graylight}Private Network Mode${clear} can deploy your ICPipeline Worker containers on either Fargate or ECS/EC2."
  echo
  echo -e "The reason we present this option only in ${graylight}Private Network Mode${clear} is that EC2-backed Dockers simply aren't"
  echo -e "configurable with public IP addresses.  If/when AWS solves for this limitation, we'll speedily implement it here in ${cyan}ICPipeline${clear}."
  echo
  echo -e "${cyan}******************************************************************************${clear}"
  echo
  pauseforuser
  echo
  echo -e "${cyan}******************************************************************************${clear}"
  echo
  echo "In reference to that first option, would you like us to stand up a VPN directly to the private subnet"
  echo -e "where your ${cyan}Workers${clear} are hosted?  This means you'll be able to SSH right into"
  echo -e "your ${cyan}Workers${clear} using their private IPs.  It's hassle-free and works really well."
  echo


  isgood=0
  while [[ $isgood == 0 ]]; do

    echo
    read -p "Would you like a VPN to go with that? (type and enter \"VPN\", or <ENTER> to skip): " add_vpn
    add_vpn=${add_vpn:-'NO'} && add_vpn=$(echo "${add_vpn}" | tr 'A-Z' 'a-z')

    while [[ ! ${add_vpn} == "no" && ! ${add_vpn} == "vpn" ]]; do invalid_response; done
    if [[ ${add_vpn} == "no" ||  ${add_vpn} == "vpn" ]]; then isgood=1; fi

  done

  echo
  echo "Thanks!   And we have that second option, of Fargate or EC2 Docker hosting.  To explain very briefly:"
  echo
  echo -e "${cyan}******************************************************************************${clear}"
  echo
  echo -e "With ${graylight}Private Network Mode${clear} you choose your preferred container infrastructure.  Your Dockerized ${cyan}Workers${clear} can run on either:"
  echo
  echo "    --> AWS Fargate"
  echo "        OR"
  echo "    --> ECS EC2 Container Instances"
  echo
  echo -e "Just so you have the full context: if this were a ${graylightbold}Public Network Mode${clear} installation, Fargate would be the only option."
  echo "This is because AWS allows only Fargate-backed containers to have public IP addresses.  So, ECS/EC2-backed containers"
  echo -e "simply can't meet the most basic requirement of ${graylight}Public Network Mode${clear}."
  echo
  echo "Whether Fargate- or EC2-backed, each Worker each has a dedicated, out-facing network interface.  So they behave \"normally\""
  echo "on the network, as full-fledged, fully reachable TCP/IP hosts.  While the native Docker networking stack has its virtues,"
  echo "in an application like this, we think the cons outweigh the pros.  We think EC2-hosted Workers should network robustly"
  echo "whether it's public or private, and that's how we built it."
  echo
  echo "To be clear, if you're uncertain here, we highly recommend that you do the reading.  Very simply put,"
  echo "Fargate is the optimally-flexible, small-footprint way to stand up a Docker platform from scratch."
  echo "ECS/EC2 container instances, on the other hand, are generally the more robust, scalable, \"enterprise\" approach."
  echo "Either service may be the more cost-effective, depending on your circumstances and requirements."
  echo "These are casual, highly generalized guidelines -- please take them at face value and in good faith. By all means,"
  echo "you should take the time to make informed choices, and be sure you're on the right track."
  echo
  echo "In any case, this shouldn't stand in the way of your perfectly good installation in-progress.  If you decide to make changes afterward,"
  echo "it's easy to reset and start over."
  echo

  sleep 3

  
  # Fargate will be the default/backstop for container infrastructure type.
  launch_mode_selection=fargate
  
  isgood=0
  while [[ $isgood == 0 ]]; do

    echo
    read -p "Please type and enter either \"FARGATE\" or \"EC2\" for your container infrastructure in AWS: " launch_mode_selection
    launch_mode_selection=${launch_mode_selection:-'NO'} && launch_mode_selection=$(echo "${launch_mode_selection}" | tr 'A-Z' 'a-z')

    while [[ ! ${launch_mode_selection} == "ec2" && ! ${launch_mode_selection} == "fargate" ]]; do invalid_response; done
    if [[ ${launch_mode_selection} == "ec2" ||  ${launch_mode_selection} == "fargate" ]]; then isgood=1; fi

  done



fi # end if private_network_mode = true


# In all cases we capture the user's selected cluster type (Fargate vs EC2) to the resetter breadcrumb trail.
echo "INSTALLER_ECS_CLUSTER_TYPE=${launch_mode_selection}" >> "${resources_dir}"/util/installation_vars.env

# **************************************************************************************************
# in public network mode only, present user option for ingress cidr block (for remote worker access)
# **************************************************************************************************

if [[ "${public_network_mode}" == true ]]
then

  echo "Here you can optionally choose to limit remote network access to your Worker containers by IP range."
  echo
  echo "If you opt to add an IP address or range in CIDR notation, only addresses in that range will be allowed to reach your Workers."
  echo
  echo "For instance, if your whole team works from the same source address (say, on the NAT'd private network behind most WiFi routers),"
  echo "you can enter that address (or a range of addresses) here, so that only matching inbound traffic will be allowed."
  echo
  echo "The default setting, in both installation modes, is the wildcard CIDR range 0.0.0.0/0"
  echo "So all inbound (IPV4) traffic (only on the authorized ports we just configured) is qualified."
  echo

  isgood=0
  while [[ $isgood == 0 ]]; do

    echo
    read -p "Add a custom ingress CIDR range? (type and enter \"CIDR\", or <ENTER> to skip): " add_ingress_cidr
    add_ingress_cidr=${add_ingress_cidr:-'NO'} && add_ingress_cidr=$(echo "${add_ingress_cidr}" | tr 'A-Z' 'a-z')

    while [[ ! ${add_ingress_cidr} == "no" && ! ${add_ingress_cidr} == "cidr" ]]; do invalid_response; done
    if [[ ${add_ingress_cidr} == "no" ||  ${add_ingress_cidr} == "cidr" ]]; then isgood=1; fi

  done

  if [[ "cidr" == "${add_ingress_cidr}" ]]
  then
  
    while true; do
  
      read -p "Ingress CIDR block: " ingress_cidr_block
      echo
      read -p "Confirm Ingress CIDR block: " ingress_cidr_block2
      echo
      
      [[ "${ingress_cidr_block}" == "${ingress_cidr_block2}" ]] || echo "CIDR blocks do not match, let's try again."

      if [[ "${ingress_cidr_block}" == "${ingress_cidr_block2}" ]]
      then
      
        [[ "$ingress_cidr_block" =~ $valid_cidr_regex ]] && break 2 || echo "Your entry is not valid CIDR notation, let's try again."
      
      fi
    
    done
  
  fi

  echo
  echo "Thank you.  Your Workers will be able to accept inbound connections from source IP addresses within range ${ingress_cidr_block}"
  echo
  echo
  echo -e "${cyan}******************************************************************************"
  echo -e "******************************************************************************${clear}"
  echo

fi # End if public_network_mode selected

# *************************************************************
# Lastly, handle user input of how many workers installer should create
# *************************************************************

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

echo -e "Lastly, please tell the installer how many containerized ${cyanbold}ICPipeline Workers${clear} you'd like to start with."
echo
echo -e "${cyan}The installer will create two Workers by default.  Press <ENTER> to skip if two is good.${clear}"
echo
echo -e "Each ${cyan}Worker${clear} will automatically connect and register with your ${cyan}Pipeline Manager${clear} d'app."
echo
echo -e "We opted for two ${cyan}Workers${clear} as the default, in order to provide a good sense of how the platform works."
echo
echo -e "A single ${cyan}Worker${clear} will do just fine -- or create as many as you like."
echo -e "You can always add more, ${cyan}Workers${clear} are pretty disposable, and one's the same as the next."
echo
echo -e "Please enter the number of ${cyan}Workers${clear} (from 1 to 9) that you'd like to start with."

while true; do
  read -p "Number of Workers (<ENTER> for default 2): " number_of_workers
  number_of_workers=${number_of_workers:-2}
  echo
  [[ "${number_of_workers}" =~ ^[0-9]{1}$ ]] && break || echo "You did not enter a number between 1 and 9, please try again."
done
echo "Thank you. The number of the counting shall be ${number_of_workers}."

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

# these brief sleeps are mostly discretionary, to smooth out the workflow,
# allow users to read and follow along better, etc.
sleep 3

# ****************************************************************************************
# ssh key copy bit only applies if this is a complete framework install, n/a if standalone
# ****************************************************************************************
if [[ true == ${include} ]]; then

  echo -e "Thank you.  And just one last detail, after which no more questions and the installer will complete your ${cyan}ICPipeline${clear}."
  echo
  echo -e "The installer always generates an SSH key pair for use when logging into your ${cyan}ICPipeline Workers${clear}."
  echo
  echo -e "Your private key file is placed here: ${green}/resources/worker-ssh-key/${worker_ssh_keyfile_name}${clear}"
  echo
  echo "You can use the key file where it is, or we can copy it to your local home folder (~/.ssh )."
  echo
  echo "We ask because this is the only time we'll do or touch anything on your machine that is outside this project folder."
  echo
  echo -e "In any case, this file is a private key that confers passwordless access to all your ${cyan}Workers${clear}, so distribute it with care."
  echo
  echo "************************************************************************************************"
  echo

  read -p "Copy Worker SSH key into your home (~/.ssh) directory? (\"YES\" to copy key): " copy_ssh_key
  copy_ssh_key=${copy_ssh_key:-'NO'} && copy_ssh_key=$(echo "${copy_ssh_key}" | tr 'A-Z' 'a-z')

fi

echo
echo -e "Thanks for your input.  ${green}You chose ${install_mode} for this installation${clear}."
echo
echo -e "Your containerized ${cyan}ICPipeline Workers${clear} will have public IP addresses, and they'll be hosted on AWS Fargate."
echo
echo "Installation will proceed according to your instructions."
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

echo "Setting up a VPC with subnet(s) to host Worker containers..."

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

# *************************************************
# create/configure subnet(s) in the VPC
# *************************************************

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
# there doesn't seems to be any output from this operation (??)
# echo "Output from enable public IPs for VPC:" >> "${aws_build_log}"
# echo "${enable_public_ip_output}" >> "${aws_build_log}"

# omit private subnet if public network mode selected by user
if [[ "${private_network_mode}" == true ]]
then
  # create private subnet in vpc (note: in the same az as public subnet)
  echo "Creating private subnet in VPC ${vpc_id} ..."
  create_private_subnet_output=$(aws ec2 create-subnet --cidr-block "${private_subnet_cidr_internal}" --availability-zone "$aws_availability_zone" --vpc-id "$vpc_id" --output json)
  echo "Output from create private subnet:" >> "${aws_build_log}"
  echo "${create_private_subnet_output}" >> "${aws_build_log}"

  # extract private subnet id (using jq)
  private_subnet_id=$(echo -e "$create_private_subnet_output" |  jq '.Subnet.SubnetId' | tr -d '"')

  # add delete private subnet entry (if exists) to aws resetter script.
  # [unlike the aws console, where deleting a vpc will take child subnets along with it, cli requires explicit subnet removal]
  echo -e "\n" >> "${aws_resetter_script_reverse}"
  echo "aws ec2 delete-subnet --subnet-id ${private_subnet_id} --output yaml-stream" >> "${aws_resetter_script_reverse}"
  echo "echo \"Deleting private subnet ${private_subnet_id} ...\"" >> "${aws_resetter_script_reverse}"

  # ref prior comment
  sleep 3

  # assign name tag to private subnet:
  echo "Tagging private subnet ${private_subnet_id} as \"${private_subnet_name_tag}\" ..."
  aws ec2 create-tags --resources "$private_subnet_id" --tags Key=Name,Value="$private_subnet_name_tag"

  # *******************************************************
  # create and config NAT gateway for private subnet egress
  # *******************************************************

  # pre-allocate elastic ip for nat gateway
  echo "Pre-allocating an Elastic IP Address for our NAT Gateway ..."
  allocate_eip_output=$(aws ec2 allocate-address --domain vpc --output json)
  echo "Output from allocate Elastic IP for NAT Gateway:" >> "${aws_build_log}"
  echo "${allocate_eip_output}" >> "${aws_build_log}"

  # extract ip address and allocation id of eip into vars (using jq)
  nat_gateway_eip_address=$(echo -e "$allocate_eip_output" | jq '.PublicIp' | tr -d '"')
  nat_gateway_eip_allocation_id=$(echo -e "$allocate_eip_output" | jq '.AllocationId' | tr -d '"')

  # create nat gateway for private subnet (note the gateway actually lives in the *public* subnet), assigning the allocated eip to it.
  echo "Creating NAT Gateway for private subnet egress, with assigned EIP ${nat_gateway_eip_address}..."
  create_nat_gateway_output=$(aws ec2 create-nat-gateway --subnet-id "${public_subnet_id}" --allocation-id "${nat_gateway_eip_allocation_id}")
  echo "Output from create NAT Gateway:" >> "${aws_build_log}"
  echo "${create_nat_gateway_output}" >> "${aws_build_log}"

  # fetch id of nat gateway into var (using jq)
  nat_gateway_id=$(echo -e "$create_nat_gateway_output" |  jq '.NatGateway.NatGatewayId' | tr -d '"')

  # tag the nat gateway
  echo "Tagging NAT Gateway as \"${nat_gateway_name_tag}\" ..."
  aws ec2 create-tags --resources "${nat_gateway_id}" --tags Key=Name,Value="${nat_gateway_name_tag}"

fi # end if ! public_network_mode

# ***************************************************************************
# create, configure Worker security group, inbound port config per user input
# ***************************************************************************
# skip the whole worker security group piece if standalone ...
if [[ true == ${include} ]]; then
  
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

fi
# a couple of separate IFs here (as opposed to being in the same conditionals above) simply to manage the order of the lines in our aws resetter.
# the nat gateway's allocated eip must be released before the worker security group will delete,
# and, it breaks if we release the eip instantly after dropping the nat gateway.  hence the built-in pause, etc.
if [[ "${private_network_mode}" == true ]]
then

  # add release nat gateway eip entry (if exists) to aws resetter script (crucial item, else subsequent detach/deletes will hang up on the still-mapped eip)
  echo -e "\n" >> "${aws_resetter_script_reverse}"
  echo "aws ec2 release-address --allocation-id ${nat_gateway_eip_allocation_id}" >> "${aws_resetter_script_reverse}"
  echo "echo \"Releasing NAT gateway EIP allocation ${nat_gateway_eip_allocation_id} ...\"" >> "${aws_resetter_script_reverse}"

  echo -e "\n" >> "${aws_resetter_script_reverse}"
  echo "sleep 90" >> "${aws_resetter_script_reverse}"
  echo "echo \"Pausing 90 seconds to allow for AWS dependencies latency ...\"" >> "${aws_resetter_script_reverse}"

  # add delete nat gateway entry (if exists) to aws resetter script
  echo -e "\n" >> "${aws_resetter_script_reverse}"
  echo "aws ec2 delete-nat-gateway --nat-gateway-id ${nat_gateway_id} --output yaml-stream" >> "${aws_resetter_script_reverse}"
  echo "echo \"Deleting NAT gateway ${nat_gateway_id} ...\"" >> "${aws_resetter_script_reverse}"

fi

# Again, IF this is full installer build,
# we need to handle the security group for Worker containers.
if [[ true == ${include} ]]; then
  
  echo -e "Configuring remote access to ${cyan}Workers${clear} ..."

  for tcp_port in "${ingress_ports_unique[@]}"
  do
    echo "Enabling remote Worker access on port ${tcp_port} ..."
    echo "Output from enable ingress to Workers on port ${tcp_port}:" >> "${aws_build_log}"
    aws ec2 authorize-security-group-ingress --group-id "${worker_security_group_id}" --protocol tcp --port "${tcp_port}" --cidr "${ingress_cidr_block}" --output json >> "${aws_build_log}"
  done

fi
# *******************************************************************************
# create, configure, apply route tables and routes for public and private subnets
# *******************************************************************************

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

if [[ true == "${private_network_mode}" ]]
then

  # create route table for private subnet
  echo "Creating route table for ${private_subnet_name_tag} ${private_subnet_id} ..."
  create_private_subnet_route_table_output=$(aws ec2 create-route-table --vpc-id "${vpc_id}" --output json)
  echo "Output from create private subnet route table:" >> "${aws_build_log}"
  echo "${create_private_subnet_route_table_output}" >> "${aws_build_log}"

  # fetch private subnet route table id
  private_subnet_route_table_id=$(echo -e "${create_private_subnet_route_table_output}" | jq '.RouteTable.RouteTableId' | tr -d '"')

  # ref prior comment
  sleep 3

  # name tag private subnet route table
  echo "Tagging private subnet route table ${private_subnet_route_table_id} as \"${private_subnet_route_table_name_tag}\" ..."
  aws ec2 create-tags --resources "${private_subnet_route_table_id}" --tags Key=Name,Value="${private_subnet_route_table_name_tag}" --output json >> "${aws_build_log}"

  # add delete private subnet route table (if exists) entry to aws resetter script (if there's one)
  echo -e "\n" >> "${aws_resetter_script_reverse}"
  echo "aws ec2 delete-route-table --route-table-id ${private_subnet_route_table_id} --output yaml-stream" >> "${aws_resetter_script_reverse}"
  echo "echo \"Deleting private subnet route table ${private_subnet_route_table_id} ...\"" >> "${aws_resetter_script_reverse}"

  # add route to private subnet route table
  echo "Configuring egress route via ${nat_gateway_name_tag} ${nat_gateway_id} for ${private_subnet_route_table_name_tag} ${private_subnet_route_table_id} ..."
  add_private_subnet_route_output=$(aws ec2 create-route --route-table-id "${private_subnet_route_table_id}" --destination-cidr-block "${egress_cidr_block}" --nat-gateway-id "${nat_gateway_id}")
  echo "Output from add private subnet route to route table:" >> "${aws_build_log}"
  echo "${add_private_subnet_route_output}" >> "${aws_build_log}"

  # associate private subnet route table with private subnet
  echo "Applying ${private_subnet_route_table_name_tag} to ${private_subnet_name_tag} ..."
  apply_private_subnet_route_table_output=$(aws ec2 associate-route-table --subnet-id "${private_subnet_id}" --route-table-id "${private_subnet_route_table_id}")
  echo "Output from apply route table to private subnet:" >> "${aws_build_log}"
  echo "${apply_private_subnet_route_table_output}" >> "${aws_build_log}"

  # fetch the association id for the route table to the private subnet (if there's one)
  private_subnet_route_table_association_id=$(echo -e "${apply_private_subnet_route_table_output}" | jq '.AssociationId' | tr -d '"')

  # add disassociate private subnet route table (if exists) from private subnet entry to aws resetter script
  echo -e "\n" >> "${aws_resetter_script_reverse}"
  echo "aws ec2 disassociate-route-table --association-id ${private_subnet_route_table_association_id}" >> "${aws_resetter_script_reverse}"
  echo "echo \"Disconnecting route table from private subnet, removing associationId ${private_subnet_route_table_association_id} ...\"" >> "${aws_resetter_script_reverse}"

  if [[ "vpn" == "${add_vpn}" ]]
  then
    
    echo
    echo -e "${cyan}******************************************************************************"
    echo -e "******************************************************************************${clear}"
    echo
    
    echo "You chose to add a VPN, so we'll refer you to the VPN module now ..."
    echo
    sleep 3

    # Call the VPN builder module if user so chose.
    source "${resources_dir}"/include/create_vpn_aws.sh

  fi # end if add_vpn

fi # end if private_network_mode

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

if [[ true == "${include}" ]]; then

  echo "AWS networking setup is complete, returning now to the main installer workflow ...  "

else

  # Standalone so we finalize the AWS resetter script right here.
  tac "${aws_resetter_script_reverse}" >> "${aws_resetter_script}"

  echo "You did a standalone run of your AWS infrastructure builder."
  echo
  echo "So you've basically got yourself one ${vpc_name_tag} to enjoy in good health."
  echo

  if [[ true == "${private_network_mode}" ]]; then

    echo "You chose Private Network Mode, so it has public and private subnets."

  else

    echo "You chose Public Network Mode, so it has just the one public subnet."

  fi

  echo "BTW, your AWS resetter script (/resources/cloudconf/aws/reset_installation_aws.sh) still works great"
  echo "with standalone infra builds like this one.  Just be aware that there's one and only one of those"
  echo "resetter scripts at any given time.  So mind your housekeeping, and maybe check /resources/archive,"
  echo "if managing multiple builds at the same time."

fi

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

sleep 3