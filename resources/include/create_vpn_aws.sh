#!/bin/bash

# This module creates a VPN connection to an AWS VPN, like so:
# -> Download the OpenVPN Easy-RSA bundle from Github
# -> Use Easy-RSA to generate a local CA and two self-signed certicates (one server, one client)
# -> Import both certs into AWS Certificate Manager
# -> Stand up an AWS Client VPN Endpoint, assigning said certificates to it
# -> Associate the VPN endpoint with an AWS subnet id (that being the ICPipeline Private Subnet)
# -> Add a wildcard authorization rule
# -> Add a wildcard egress route to the world
# -> Download the AWS client configuration (.ovpn) file in its half-baked state
# -> Make further edits to the client config file (inject the client certificate and some routing rules),
#    making it ready for import-and-connect with any OpenVPN-based client.

# NOTE: this script is not *fully* modularized at present, i.e. it's not quite functional as a standalone tool.
# Indeed, it runs relative to a different location than where it physically sits, as an include of the main installer.
# It is a very nice VPN builder, and it will soon be good to as such, all by itself.

# Client CIDR block: essentially the DHCP pool of addresses assigned to connecting clients by the VPN endpoint.
# This range must not overlap with the internal range of any network it's connecting to,
# OR with anything else in the user's IP stack.  ICPipeline uses "10.100..." address ranges for all internal
# private networking, so this gets "192.168.100...".  This way they're clear of each other, while the .100 in the third
# octet should also keep clear of the defaults in most folks' existing stacks.  The only reason to tweak this stuff is if you have
# other things going on that collide, for whatever reason.
# If you do make changes, note that the mask bits (the number after the slash)
# must be nlt /12 and ngt /22.  That is an AWS limitation.
# /22 allots ~1K host addresses to work with ... if you need more than that, you may already be qualified for ICPipeline enterprise support.
client_cidr_block="192.168.100.0/22"
# [usable range 192.168.100.0 <> 192.168.103.255]

# These are the names assigned to the two VPN certificates, which are created locally and imported into ACM
# during configuration of the AWS Client VPN Endpoint.
# Tweak to suit, but be advised that we don't validate this.
# So if you change them, rtm for naming convention constraints, etc.
# This adheres to dot.syntax.naming, because it's called "domain name", but in this context
# (basically self-signed certs acting as key pairs), I think they could be Abbott and Costello.  What we know for sure is that these names work.
server_cert_name="server.cert.icpipeline.vpn"
client_cert_name="client.cert.icpipeline.vpn"

# Set so the VPN will connect to the "ICPipeline Private Subnet" of your "ICPipeline VPC" (i.e. what it's here for).
# But you could point it at either defined subnet, if you had a reason to do so.
target_subnet_id="${private_subnet_id}"
# The internal cidr range of the same subnet (final "modularization" pass will replace this with an API call referencing the subnet ID)
target_subnet_cidr_internal=${private_subnet_cidr_internal}

# The VPN's transport protocol -- UDP vs TCP.  Rules of thumb for reference:
# UDP = faster, but without error checking
# TCP = slower, with native error checking
# Real-world, the UDP speed difference is tangible, and impactful errors are very rare.
# We default to UDP, as do AWS and general standard practice -- i.e. UDP is default when the --transport-protocol flag is omitted.
# You may consider TCP if, say, you're doing stateful database connections over the tunnel...in that case we'd likely opt for TCP and take the speed hit.
# Otherwise UDP, being noticeably more performant, is the standard practice.
vpn_transport_protocol="udp"

# Initialize VPN build logfile
vpn_build_log="${resources_dir}"/installer-logs/vpn.build.log
touch "${vpn_build_log}" || exit_on_err "Installer was unable to create file vpn.build.log"

# Create an identifiable named folder in /resources and designate the client config file name.
# (FYI if you make changes here, retain the .ovpn filename suffix which most clients insist on)
mkdir "${resources_dir}"/vpn-client-config && vpn_client_config_file="${resources_dir}/vpn-client-config/icpipeline_vpn_client_config.ovpn"

# ******************************************************
# Deal with CIDR-to-decimal notation of IP, netmask etc.
# ******************************************************

# Split target CIDR block into address and netmask on "/" delimiter
# The address part
target_subnet_unmasked=$(echo "$target_subnet_cidr_internal" | awk -F'/' '{print $1}')
# The subnet mask part
target_subnet_netmask=$(echo "$target_subnet_cidr_internal" | awk -F'/' '{print $2}')

# Convert stripped subnet mask from slash notation to decimal
# This is awful form I know ... and only works from /16 to /28, egads.
# Bash and I are both terrible at math, didn't want to create another system requirement by dragging in Py ...
# Anyway, brain tired, will replace w/something nice (or by all means do jump in, send us a PR :D) ... meantime this is reliable.
if [[ ${target_subnet_netmask} == 16 ]]
then
  target_subnet_netmask_decimal="255.255.0.0"
elif  [[ ${target_subnet_netmask} == 17 ]]
then
  target_subnet_netmask_decimal="255.255.128.0"
elif  [[ ${target_subnet_netmask} == 18 ]]
then
  target_subnet_netmask_decimal="255.255.192.0"
elif  [[ ${target_subnet_netmask} == 19 ]]
then
  target_subnet_netmask_decimal="255.255.224.0"
elif  [[ ${target_subnet_netmask} == 20 ]]
then
  target_subnet_netmask_decimal="255.255.240.0"
elif  [[ ${target_subnet_netmask} == 21 ]]
then
  target_subnet_netmask_decimal="255.255.248.0"
elif  [[ ${target_subnet_netmask} == 22 ]]
then
  target_subnet_netmask_decimal="255.255.252.0"
elif  [[ ${target_subnet_netmask} == 23 ]]
then
  target_subnet_netmask_decimal="255.255.254.0"
elif  [[ ${target_subnet_netmask} == 24 ]]
then
  target_subnet_netmask_decimal="255.255.255.0"
elif  [[ ${target_subnet_netmask} == 25 ]]
then
  target_subnet_netmask_decimal="255.255.255.128"
elif  [[ ${target_subnet_netmask} == 26 ]]
then
  target_subnet_netmask_decimal="255.255.255.192"
elif  [[ ${target_subnet_netmask} == 27 ]]
then
  target_subnet_netmask_decimal="255.255.255.224"
elif  [[ ${target_subnet_netmask} == 28 ]]
then
  target_subnet_netmask_decimal="255.255.255.240"
fi

# *************************************************************************************
# Clone easy-rsa repo from github, generate local faux CA, issue certs and private keys
# *************************************************************************************

echo
echo "Welcome to the ICPipeline VPN module.  It will (wait for it) build your VPN, using OpenVPN tools and AWS services."
echo
echo "We'll download OpenVPN Easy-RSA into a subdirectory in /resources.  All its activity and output is confined"
echo "within this project.  It's non-invasive, your privacy is top-of-mind as always."
echo
echo "And away we go ..."
sleep 4

echo "Retrieving OpenVPN Easy-RSA bundle from Github ..."
git clone https://github.com/OpenVPN/easy-rsa.git "${resources_dir}"/util/easy-rsa
easy_rsa_dir="${resources_dir}"/util/easy-rsa
echo "${easy_rsa_dir}"

# these easy-rsa commands are in subshells, minding locations, paths, etc.
# initialize local "certificate authority" (placing pki directory inside /easy-rsa,
# the /pki dir is where the actual certs and keys are placed).
echo
echo "Initializing local certificate authority ..."
echo
(cd "${resources_dir}"/util/easy-rsa && "${easy_rsa_dir}"/easyrsa3/easyrsa init-pki >> "${vpn_build_log}")

# build ca, piping <enter> to the one question it asks (i.e. "Common Name", which i think defaults to OpenVPN something)...
echo
echo "Building local CA ..."
echo
(cd "${resources_dir}"/util/easy-rsa && echo -ne '\n' | "${easy_rsa_dir}"/easyrsa3/easyrsa build-ca nopass >> "${vpn_build_log}")

# *************************************************************************************************************
# generate both server and client certificates
# (note also that this implements a single cert for "client"...real-world/best practice would be cert-per-user)
# *************************************************************************************************************

# Generate the server certificate/key
echo
echo "Generating server certificate and private key ..."
echo

(cd "${resources_dir}"/util/easy-rsa && "${easy_rsa_dir}"/easyrsa3/easyrsa build-server-full "${server_cert_name}" nopass >> "${vpn_build_log}")

# Generate the client certificate/key
echo
echo "Generating client certificate and private key ..."
echo

(cd "${resources_dir}"/util/easy-rsa && "${easy_rsa_dir}"/easyrsa3/easyrsa build-client-full "${client_cert_name}" nopass >> "${vpn_build_log}")

# Now we have:
  # Two certificates (self-signed, really just public/private key pairs).
  # Two private keys, one for each certificate.
# Everything is clearly named, in these locations:
  # Certificates go in:
    # /resources/util/easy-rsa/easyrsa3/pki/issued/
  # Private keyfiles go in:
    # /resources/util/easy-rsa/easyrsa3/pki/private/

# *****************************************************************************************
# Import certificates into AWS Certificate Manager, extract their assigned certificate ARNs
# *****************************************************************************************

# Import server certificate into ACM
echo
echo "Importing server certificate into AWS Certificate Manager ..."
echo
import_server_cert_output=$(aws acm import-certificate --certificate fileb://"${easy_rsa_dir}"/pki/issued/"${server_cert_name}".crt --private-key fileb://"${easy_rsa_dir}"/pki/private/"${server_cert_name}".key --certificate-chain fileb://"${easy_rsa_dir}"/pki/ca.crt --region "${aws_region}")

# Extract server certificate ARN
server_certificate_arn=$(echo -e "${import_server_cert_output}" | jq '.CertificateArn' | tr -d '"')
echo
echo "Server certificate ARN assigned by AWS: ${server_certificate_arn}"
echo

# Add delete-certificate (server cert) entry to AWS resetter script
echo -e "\n" >> "${aws_resetter_script_reverse}"
echo "aws acm delete-certificate --certificate-arn ${server_certificate_arn} --output yaml-stream" >> "${aws_resetter_script_reverse}"
echo "echo \"Deleting VPN server certificate ${server_certificate_arn} from ACM ...\"" >> "${aws_resetter_script_reverse}"

# Import client certificate into ACM
echo
echo "Importing client certificate into AWS Certificate Manager ..."
echo
import_client_cert_output=$(aws acm import-certificate --certificate fileb://"${easy_rsa_dir}"/pki/issued/"${client_cert_name}".crt --private-key fileb://"${easy_rsa_dir}"/pki/private/"${client_cert_name}".key --certificate-chain fileb://"${easy_rsa_dir}"/pki/ca.crt --region "${aws_region}")

# Extract client certificate ARN
client_certificate_arn=$(echo -e "${import_client_cert_output}" | jq '.CertificateArn' | tr -d '"')
echo
echo "Client certificate ARN assigned by AWS: ${client_certificate_arn}"
echo

# Add delete-certificate (client cert) entry to aws resetter script
echo -e "\n" >> "${aws_resetter_script_reverse}"
echo "aws acm delete-certificate --certificate-arn ${client_certificate_arn} --output yaml-stream" >> "${aws_resetter_script_reverse}"
echo "echo \"Deleting VPN client certificate ${client_certificate_arn} from ACM ...\"" >> "${aws_resetter_script_reverse}"

# ***********************************************************************
# Create Client VPN Endpoint, assigning the two hosted certificates to it
# ***********************************************************************

echo
echo "Creating VPN Client Endpoint ..."
echo
create_vpn_endpoint_output=$(aws ec2 create-client-vpn-endpoint \
--transport-protocol "${vpn_transport_protocol}" \
--client-cidr-block "${client_cidr_block}" \
--server-certificate-arn "${server_certificate_arn}" \
--authentication-options Type=certificate-authentication,MutualAuthentication={ClientRootCertificateChainArn="${client_certificate_arn}"} \
--connection-log-options Enabled=false)

# Extract the Client VPN Endpoint id
vpn_endpoint_id=$(echo -e "${create_vpn_endpoint_output}" | jq '.ClientVpnEndpointId' | tr -d '"')

# Add delete-client-vpn-endpoint entry to aws resetter script
echo -e "\n" >> "${aws_resetter_script_reverse}"
echo "aws ec2 delete-client-vpn-endpoint --client-vpn-endpoint-id ${vpn_endpoint_id} --output yaml-stream" >> "${aws_resetter_script_reverse}"
echo "echo \"Deleting VPN Client Endpoint ${vpn_endpoint_id} from ACM ...\"" >> "${aws_resetter_script_reverse}"


echo "VPN Client Endpoint ID: ${vpn_endpoint_id}"
echo

# Associate the VPN endpoint with the private subnet, extract association id for use in resetter script build
echo
echo "Associating VPN endpoint ${vpn_endpoint_id} with subnet ${target_subnet_id} ..."
echo
associate_vpn_endpoint_output=$(aws ec2 associate-client-vpn-target-network --client-vpn-endpoint-id "${vpn_endpoint_id}" --subnet-id "${target_subnet_id}")
vpn_endpoint_association_id=$(echo -e "${associate_vpn_endpoint_output}" | jq '.AssociationId' | tr -d '"')

# Add disassociate-client-vpn-target-network (private subnet) entry to aws resetter script
echo -e "\n" >> "${aws_resetter_script_reverse}"
echo "aws ec2 disassociate-client-vpn-target-network --client-vpn-endpoint-id ${vpn_endpoint_id} --association-id ${vpn_endpoint_association_id} --output yaml-stream" >> "${aws_resetter_script_reverse}"
echo "echo \"Disassociating VPN Client Endpoint ${vpn_endpoint_id} from subnet ${target_subnet_id} ...\"" >> "${aws_resetter_script_reverse}"

# Add authorization rule to Client VPN Endpoint
echo
echo "Adding authorization rule to VPN Client Endpoint ..."
echo
aws ec2 authorize-client-vpn-ingress --client-vpn-endpoint-id "${vpn_endpoint_id}" --target-network-cidr "${target_subnet_cidr_internal}" --authorize-all-groups >> "${vpn_build_log}"

# Add egress route
# (NOTE this route may in fact be unnecessary in this case.  We expressly route *only* internal-destination client packets through the tunnel.
# So, there is no through-traffic, so egress is not really a thing.  Give us a ping if you agree/disagree/confirm, etc.)
echo
echo "Adding egress route to VPN Client Endpoint ..."
echo
aws ec2 create-client-vpn-route --client-vpn-endpoint-id "${vpn_endpoint_id}" --destination-cidr-block 0.0.0.0/0 --target-vpc-subnet-id "${target_subnet_id}"

# Download the client config file, which can be imported into any OVPN-based client, which will still require work in order to be usable.
echo
echo "Downloading client configuration file for VPN Client Endpoint ..."
echo
# Echoes out the command ... if sanity check and quirk chasing ...
# echo "aws ec2 export-client-vpn-client-configuration --client-vpn-endpoint-id ${vpn_endpoint_id} --output text > ${vpn_client_config_file}"

aws ec2 export-client-vpn-client-configuration --client-vpn-endpoint-id "${vpn_endpoint_id}" --output text > "${vpn_client_config_file}"

# Verify that the VPN client config file has downloaded (technically just that *something* has downloaded)

if [ -f "${vpn_client_config_file}" ]; then
    
  # Make edits to the vpn client config (.ovpn) file:
  # First inject a routing rule, so that *only* packets with internal destinations
  # will route through the tunnel...i.e. being connected won't tangle with client's internet access etc.
  # Set it so client-side directives will take precedence over any conflicting server-side rules.

  # Then, we inject the client cert and key into the client config file.
  # Once complete, the file should be good go to -- user can just import, click to connect and she nails right up.
  echo "Making some final edits to your VPN client configuration file (in /resources/vpn-client-config) ..."
  echo
  echo "Note that we add a client-side routing rule so that *only* internal-destination packets route through the VPN ..."
  echo
  echo -e "${green}So your regular network activity stays private, and works normally, while you're connected.${clear}"
  echo
  sleep 5

  echo -e "\n" >> "${vpn_client_config_file}"
  echo -e "# client config will *rump any conflicting server-side rules" >> "${vpn_client_config_file}"
  echo -e "pull-filter ignore \"redirect-gateway\"" >> "${vpn_client_config_file}"
  echo -e "# route only internal-destination packets through the tunnel" >> "${vpn_client_config_file}"
  echo -e "route ${target_subnet_unmasked} ${target_subnet_netmask_decimal}" >> "${vpn_client_config_file}"

  echo -e "\n" >> "${vpn_client_config_file}"
  echo -e "\n" >> "${vpn_client_config_file}"
  echo -e "<cert>" >> "${vpn_client_config_file}"
  echo -e "\n" >> "${vpn_client_config_file}"
  sed -n '/-----BEGIN CERTIFICATE-----/,$p' "${easy_rsa_dir}"/pki/issued/"${client_cert_name}".crt >> "${vpn_client_config_file}"
  echo -e "\n" >> "${vpn_client_config_file}"
  echo -e "</cert>" >> "${vpn_client_config_file}"
  echo -e "\n" >> "${vpn_client_config_file}"
  echo -e "<key>" >> "${vpn_client_config_file}"
  cat "${easy_rsa_dir}"/pki/private/"${client_cert_name}".key >> "${vpn_client_config_file}"
  echo -e "\n" >> "${vpn_client_config_file}"
  echo -e "</key>" >> "${vpn_client_config_file}"

else

  echo "It appears that the VPN module was unable to retrieve your VPN client config file from the AWS API."
  echo "This is unfortunate.  But it's only the client config file, and it should be available via the AWS console."
  echo "And it won't be connect-ready the way it ships from the API, VPN module usually takes care of the rest,"
  echo "which unfortunately has not happened in this case because we don't have the file."
  echo
  echo "Candidly, if this happened to us we'd just start over.  Just run the ICPipeline resetter, which will roll"
  echo "everything back clean (yes, everything: locally, in AWS and on the IC).  Then run the installer again from scratch."
  echo
  echo "We are interested to hear from you (particularly with things like this).  We'll be glad to try and help"
  echo "if you touch base with us: support@icpipeline.com"

fi

echo "VPN build and configuration is complete, rejoining the AWS network module ..."
echo

sleep 2
