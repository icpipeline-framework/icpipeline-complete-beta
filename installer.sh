#!/bin/bash

# This is an installer program for ICPipeline, the development catalyst for the Internet Computer.
# This installer, when executed on a workstation with standard Node/React tools, stands up an end-to-end deployment
# of the ICPipeline framework that is entirely controlled and operated by the user.  There is no co-tenancy or shared resources,
# no piping of data back to any central node or entity.

# The installer will produce either of two architecture modes: "Private Network Mode" or "Public Network Mode".
# This applies to the network architecture of the containerized Workers component.
# The user chooses during installation.  Refer to runtime screen output and/or the README for more info.

# This script works in conjunction with its helper scripts.  It makes considerable use of bash's liberal variable scoping.
# So, if your bash debugger is going nuts, that's (partly, anyway) because it sees what may appear to be declared-but-not-invoked variables.
# We did this to compartmentalize and place things in context, hopefully in aid of a more readable code base.

# This particular variable handles "branching" across multiple sets of repos ... as we address multiple audience cohorts, etc.
# It allows for an otherwise-identical codebase across repos while avoiding /the/path/discrepancies that 
# would otherwise arise.  It's propagated through the framework components: installer, resetter, internal modules, etc.
# It has material effects on all the above, so please handle with care.
# For end-users it will always come preset correctly (usually =""), and
# AT NO TIME SHOULD NORMAL USE OF THE FRAMEWORK ENTAIL CHANGING OR TOUCHING THIS.
git_repo_suffix=-beta

# Utility functions and cosmetics.  It really deserves a more important-sounding name at this point.
source ./resources/include/formatting.sh

# Print logo ascii "art" ... huzzah ... needs work.
cat ./resources/media/ascii_logo_b64.txt | base64 -d

# Disclosure blurb module.  Accommodates short-version/long-version user option.
source ./resources/include/full_disclosure.sh

# We default, by default, to the more-secure option, which in this case is Private Network Mode (no need to change it here, installer UI presents the option).
# This is mutually exclusive, where a single true/false var would have covered the logic, did it this way for readability.
private_network_mode=true && public_network_mode=false
# This one is display-only, no logic attached.
install_mode="Private Network Mode"

# Validate user-input CIDR notation (cheers to Mark Hatton in UK for this lovely regex)
valid_cidr_regex='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(3[0-2]|[1-2][0-9]|[0-9]))$'

# Validate user-input port numbers
valid_port_regex='^([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$'

# Set a filename for worker ssh keyfile (handle with care)
# IMPORTANT: if you change this:
# 1. You'll need to tweak two other places where (sorry to say) it's hard-coded for the moment:
#   a) in the docker setup script (setup.sh), which copies the public keyfile into authorized_keys on each container
#   b) in the resetter script (reset_installation_main.sh).  There it's less critical, but update your installer_artifacts array for clean reset.
# 2. Also, avoid choosing the exact same name as another file in this same directory, because ...
# Farther down (~line 700) you can switch pubkey algo ...rsa, ed25519 etc.
# It's not hard-coded because we have plans going forward (and really best just left as-is).
worker_ssh_keyfile_name="id_ed25519_icpipeline"

# A vestigial error handling widget, work in progress.
THIS=$(basename "$0")
exit_on_err(){
  echo "${THIS}: ${1:-"Unknown Error"}" 1>&2
  echo "${THIS} will exit so this can be remedied."
  exit 1
}

# This suppresses pagination of verbose AWS CLI outputs; may avert the need for user intervention where unwanted.
export AWS_PAGER=""

# Project home orients itself to the location of this installer on the local filesystem.
project_home_dir="$(pwd)"

# Submodule directory names with reference to repo-suffix above.
icpm_dir_name="manager${git_repo_suffix}"
icpw_dir_name="worker-docker${git_repo_suffix}"
# Not referenced at present, setting for completeness and you never know ...
uplink_dir_name="uplink${git_repo_suffix}"

# Set module paths with reference to project_home
icpm_dir="${project_home_dir}/${icpm_dir_name}"
icpw_dir="${project_home_dir}/${icpw_dir_name}"
# again, uplink dir just for housekeeping at present
# uplink_dir="${project_home_dir}/${uplink_dir_name}"
resources_dir="${project_home_dir}/resources"

# Here we set the pieces to dynamically compile a takedown script that will remove AWS resources created by the installer.
# We compile the delete commands as we go, then basically play them back in reverse order -- last-in/first-out to avoid AWS dependency hell.
# [note, the line-by-line writes mostly come from the module script includes.]
# Initialize the backwards version, which compiles as we go ...
aws_resetter_script_reverse="${resources_dir}/cloudconf/aws/aws_deletes_reverse_order.tmp"
# Start both files clean in case remnants exist.
: > "${aws_resetter_script_reverse}"
# Initialize the final product script ... this sits idle until we tac the backwards one into it at the end.
aws_resetter_script="${resources_dir}/cloudconf/aws/reset_installation_aws.sh"
: > "${aws_resetter_script}"
# Add shebang and set the execute bit ...
echo "#!/bin/bash" > "${aws_resetter_script}" && chmod +x "${aws_resetter_script}" 

# Installer compiles a .env file that goes into the docker build
# as reference for worker config, worker<>manager comms, etc.
# once copied into the docker, this file has no direct function on this side.
# the local copy is kept for reference, troubleshooting, etc.
dotenv_file="${project_home_dir}/worker.config.env"

# Check for any .env remnants, possible leftovers from a previous partial install.
f="${dotenv_file}"
if [ -f "${f}" ]
then
  rm -f "${f}"
  touch "${f}"
else
  touch "${f}"
fi
unset f

# Each install generates its own pseudo-random token
# for authenticating ICPL worker<>manager calls.  That's mandatory so we exit on fail.
icpm_auth_token="icpl_$(openssl rand -hex 21)" || exit_on_err "Installer was unable to generate an auth token with ssh keygen."

echo "ICPM_AUTH_TOKEN=${icpm_auth_token}" | xargs >> "${dotenv_file}"
echo "DEBUG_MODE=OFF" | xargs >> "${dotenv_file}"
echo "WORKER_MODE=PROD" | xargs >> "${dotenv_file}"
echo "GIT_REPO_SUFFIX=${git_repo_suffix}" | xargs >> "${dotenv_file}"

# Inject the auth token into Manager d'app canister code
echo "module {" > ./token.mo
echo "  public func getApiToken() : Text {" >> ./token.mo
echo "    let apiKey: Text = \"${icpm_auth_token}\";" >> ./token.mo
echo "    return apiKey;" >> ./token.mo
echo "  } // end func" >> ./token.mo
echo "} // end module" >> ./token.mo

# Copy token file into the Manager d'app module, delete workfile copy, exit on fail.
cp -f ./token.mo "${icpm_dir}"/src/icpm/token.mo || exit_on_err "Copy of token.mo file failed."
rm -f ./token.mo || exit_on_err "Installer was unable to remove workfile copy of token.mo file."

# Installer appends a psuedorandom numeric suffix to ECS/Docker resource names.
# This essentially bundles the resources for a build.
# ... for a bit more "entropy" than RANDOM's native 32767 limit.
sol=99
re=$(($RANDOM%sol))
mi=$(($RANDOM%sol))
fa=$(($RANDOM%sol))
session_random=$re$mi$fa

# ***********************************************
# initialize installer logs for aws, node and dfx
# ***********************************************

# Initialize AWS build logfile
aws_build_log="${resources_dir}"/installer-logs/aws.build.log
touch "${aws_build_log}" || exit_on_err "Installer was unable to create file aws.build.log"

# Initialize NPM build logfile
npm_build_log="${resources_dir}"/installer-logs/npm.build.log
touch "${npm_build_log}" || exit_on_err "Installer was unable to create file npm.build.log file."

# Initialize DFX build logfile
dfx_build_log="${resources_dir}"/installer-logs/dfx.build.log
touch "${dfx_build_log}" || exit_on_err "Installer was unable to create file dfx.build.log file."

# Cheers to asheroto on github for this improved dotenv read-in.
export $(echo $(cat worker.config.env | sed 's/#.*//g' | sed 's/\r//g' | xargs) | envsubst)

# *********************************************
# screen output and user interaction start here
# *********************************************

# ********************************
# System requirements verification.
# ********************************

system_checks_ok=true

echo
echo -e "${cyan}******************************************************************************${clear}"
echo

echo "Verifying AWS CLI, AWS account and user profile configuration ..."
echo

# **************************************************************
# set up aws-related vars etc, verify CLI, account, profile, etc
# **************************************************************

# verify and log aws cli status on user's system
aws_cli_version="$(aws --version)"
aws_cli_location="$(which aws)"

# Write a header of sorts to our AWS build log.
echo "AWS CLI version ${aws_cli_version} @ ${aws_cli_location}" >> "${aws_build_log}"
echo "NOTE: this file is not valid JSON, YAML, etc. in its present state." >> "${aws_build_log}"
echo "It just captures outputs from the AWS APIs, with our reasonable efforts at labeling them, as they occur in the workflow." >> "${aws_build_log}"

# message user and exit if no AWS CLI, install is non-starter without it.
if [ -z "${aws_cli_location}" ]
then
  echo -e "${red}The installer can't locate the AWS CLI present on your system.${clear}"
  echo "This setup requires the AWS CLI and a configured AWS/IAM user profile."
  echo "This is something that needs your attention -- can't just do a blind \"install\" and go."
  echo "This installer will exit now.  Please try again after configuring your AWS CLI profile."
  system_checks_ok=false
  exit_on_err "AWS CLI not found on system"
fi

# fetch aws account id from user's aws profile, write it to .env file (using jq)
aws_account_id=$(aws sts get-caller-identity | jq '.Account' | tr -d '"')
echo "AWS_ACCOUNT_ID=${aws_account_id}" | xargs >> "${dotenv_file}"

# likewise aws region
aws_region=$(aws configure get region)
echo "AWS_REGION=${aws_region}" | xargs >> "${dotenv_file}"

# ...and availability zone.
# note that this returns the "first" availability zone (meaning @position[0] in the returned array from aws api)
# in the user profile's designated region. (using jq)
aws_availability_zone=$(aws ec2 describe-availability-zones --region ${aws_region} | jq '.AvailabilityZones[0].ZoneName' | tr -d '"')
echo "AWS_AVAILABILITY_ZONE=${aws_availability_zone}" | xargs >> "${dotenv_file}"

# some basic status check for aws profile completeness; otherwise, try to point the user in
# the right direction.  this can be somewhat obtuse on the aws side.
if [ -z "${aws_account_id}" ]
then
  echo -e "${red}Installer is unable to detect an AWS account id in your AWS profile configuration.${clear}"
  echo "It seems your AWS profile will need some attention before we can proceed."
  echo "The installer will exit now, to allow you to take care of that,"
  echo "after which you can re-run this installer."
  echo "AWS documentation is the best resource for help with your profile configuration."
  system_checks_ok=false
  exit_on_err "AWS Account not found."
fi

if [ -z "${aws_region}" ]
then
  echo "Your AWS CLI profile does not seem to be configured with a default region."
  echo "You should be able to use \"aws configure\", to set your profile's default region."
  echo "The installer will exit to give you a chance to do that,"
  echo "after which you can re-run the installer."
  system_checks_ok=false
  exit_on_err "AWS region not found in profile."
fi

echo
echo "This information is direct from your active AWS profile.  It's important because it tells the installer where"
echo "to create your framework's AWS resources, while providing the account privileges necessary to do so."
echo

profile_strlen=${#AWS_PROFILE}

if [ "$profile_strlen" -gt 0 ]
then
  
  echo -e "Your current selected AWS_PROFILE is ${graylightbold}${AWS_PROFILE}${clear}"

else

  echo -e "${yellow}IMPORTANT, please read:${clear}"
  echo
  echo "Active AWS_PROFILE not specified."
  echo
  echo "You do not seem to have a specifically selected AWS profile at the moment."
  echo -e "If you use a single default AWS profile, ${green}that is perfectly fine, no worries, please proceed${clear}."
  echo
  echo -e "However, ${yellow}if you are using named profiles with the AWS CLI${clear},"
  echo "please take a moment to verify that your \$AWS_PROFILE environment variable is set"
  echo "to the name of the profile you want to use.  It's important because the installer"
  echo "refers to your profile for basic information affecting A) what goes where,"
  echo "and B) whether it (i.e. you) will have the permissions required for execution."
  echo
  echo "For more information, refer to:"
  echo "https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html"

fi

echo

echo -e "The installer will deploy your ${cyanbold}ICPipeline Workers${clear} and supporting infrastructure"
echo "in accordance with these profile settings:"
echo

if [ "$profile_strlen" -lt 1 ]
then

  echo -e "${yellow}Active AWS_PROFILE: default${clear}"

else

  echo -e "Active AWS Profile: ${graylightbold}$AWS_PROFILE${clear}"

fi

echo -e "AWS account id: ${graylight}${aws_account_id}${clear}"
echo -e "AWS region: ${graylight}${aws_region}${clear}"
echo -e "AWS availability zone: ${graylight}${aws_availability_zone}${clear}"
echo

if [[ ! $(echo ${aws_cli_version} | grep 'aws-cli/2.') ]]; then

  echo "You don't seem have Version 2 of the AWS CLI installed."
  echo "CLI Version 1 may indeed work.  We're not doing anything particularly exotic with it."
  echo "But the installer is built and tested on Version 2 exclusively."
  echo
  echo "We recommend that you leave this here, upgrade your AWS CLI to version 2 before proceeding."
  echo
  echo "For your reference:"
  echo "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
  echo
  echo "Or else you can let it ride with version 1, your call.  You might even touch base and let us know how it worked out, which we'd appreciate."
  echo "Either way, press <ENTER> when you're ready to proceed."
  system_checks_ok=false
  pauseforuser

else
  echo
  echo -en "${green}(Your AWS CLI is the recommended version 2)${clear}"
  echo -en " ... "
  greencheck
  echo

fi

echo
echo "Please take a moment to confirm that your AWS profile settings are good."
echo "Mainly, if you're using multiple named AWS profiles, that this is the profile you want to use."
echo
echo "Default is fine if you just use the one profile."
echo
echo "(To change profiles, <CONTROL-C> to exit now, and restart the installer after making the switch.)"
echo
pauseforuser

# installation_vars.env is the installer's breadcrumb trail for the resetter (if/when that's needed in future).
# touch or truncate as the case may be ...
:> ${resources_dir}/util/installation_vars.env
echo "INSTALLER_AWS_PROFILE=${AWS_PROFILE}" >> ${resources_dir}/util/installation_vars.env

# write our branch suffix for the resetter, which is also full o' path stuff
echo "INSTALLER_GIT_REPO_SUFFIX=${git_repo_suffix}" >> ${resources_dir}/util/installation_vars.env


echo -e "${cyan}******************************************************************************${clear}"
echo

# preliminary check that the repo appears whole
echo -en "Verifying ICPipeline modules present ..."

# verify that core directories are set and present
if [ ! -d "${project_home_dir}" ] || [ ! -d "${icpm_dir}" ] || [ ! -d "${icpw_dir}" ] || [ ! -d "${resources_dir}" ]; then
  exit_on_err "Unable to verify ICPipeline folder structure -- you may not have cloned *--recursive* from Github...?? "
else

  sleep 1
  echo -en " "
  greencheck
  sleep 1

fi

echo -e "${cyan}******************************************************************************${clear}"
echo

echo -n "Verifying Node/NPM ..."

# verify and log node/npm status on user's system
node_location="$(which node)"
node_version="$(node --version)"
npm_location="$(which npm)"
npm_version="$(npm --version)"
echo "NodeJS version ${node_version} @ ${node_location}" >> "${npm_build_log}"
echo "NPM version ${npm_version} @ ${npm_location}" >> "${npm_build_log}"

if [ -z "${npm_location}" ]
then
  echo -e "${red}NPM not detected on system.${clear}"
  echo "The installer requires a working Node/NPM setup on your machine."
  echo "Better if you manage Node/NPM separately, to your liking."
  echo "The installer will exit now.  Please try again after setting up Node/NPM on your machine."
  system_checks_ok=false
  exit_on_err "Node not found on system."
fi

sleep 1
echo -en " "
greencheck
sleep 1

echo -e "${cyan}******************************************************************************${clear}"
echo

echo -n "Verifying Docker Engine present and running ..."

verify_docker_output_mac=$( ( ps aux | grep 'com.docker.vpnkit' | grep -v grep ) 2>&1 )
verify_docker_output_ubuntu=$( ( ps aux | grep 'dockerd' | grep -v grep ) 2>&1 )

if [[ ${#verify_docker_output_mac} == 0 && ${#verify_docker_output_ubuntu} == 0 ]]
then
  
  echo
  swsh
  echo
  echo -e "${yellow}The installer is unable to detect the Docker Engine running on your system.${clear}"
  echo
  echo -e "${cyan}ICPipeline${clear} installation requires a running Docker Engine."
  echo
  echo "However, in order to prevent potential interference with your other Docker activities, the installer steers"
  echo "clear of trying to start, restart, etc. Docker on your system.  We do not want to break your stuff."
  echo
  echo "So we'll pause and ask you to verify that Docker is definitely running on this machine."
  echo
  echo "Most Mac users will just need to start the Docker Desktop."
  echo
  echo -e "${yellow}Please allow a moment (or two) for Docker to come all the way up before we proceed."
  echo "It's ready when the little fish icon in your menu bar stops ... percolating.  The interval"
  echo -e "varies, and we will reverify it right after you hit Go.${clear}"
  echo

  read -p "Press <ENTER> when you're sure Docker is fully up, and the installer will proceed ..." kramden

  reverify_docker_output_mac=$( ( ps aux | grep 'com.docker.vpnkit' | grep -v grep ) 2>&1 )
  reverify_docker_output_ubuntu=$( ( ps aux | grep 'dockerd' | grep -v grep ) 2>&1 )

  if [[ ${#reverify_docker_output_mac} -gt 0 || ${#reverify_docker_output_ubuntu} -gt 0 ]]
  then
    
    echo -e "${green}Et voila.  Docker now appears to be alive and well, proceeding with your installation.  Thanks!${clear}"
  
  else

    echo
    echo -e "Hmmm.  ${yellow}The installer still isn't detecting a running Docker Engine on your system.${clear}"
    echo
    echo -e "${yellow}Docker is a bit trickier to verify than most system requirements, so this *might* be (not likely) a false alarm.${clear}"
    echo
    echo "We promise we're not trying to be difficult.  But the installer relies on Docker, and it's much better not to learn"
    echo "the hard way, deep in the installation process, that Docker is not up."
    echo
    echo "If this is a false alarm and you're sure Docker is running, you can enter \"GO\" below to proceed with your installation."
    echo
    echo "But it's more likely that Docker is not installed, or not fully up, on your machine."
    echo
    echo "If you agree, press <ENTER> to exit the installer now."
    echo
    echo "In that case, we hope you'll try again soon -- perhaps run the installer on a different machine."
    echo
    
    system_checks_ok=false
    
    read -p "Continue installing without Docker verification? (type and enter \"GO\" to proceed, <ENTER> to quit): " proceed_docker_unverified
    proceed_docker_unverified=${proceed_docker_unverified:-'NO'} && proceed_docker_unverified=$(echo "${proceed_docker_unverified}" | tr 'A-Z' 'a-z')

    if [[ "go" == "${proceed_docker_unverified}" ]]
    then
      
      echo "Alrighty then, proceeding with ICPipeline installation."
    
    else
    
      echo "Thank you.  We hope to see you again soon."
      system_checks_ok=false
      exit_on_err "User opted not to continue after failing Docker verification."
    
    fi

  fi

fi

sleep 1
echo -en " "
greencheck
sleep 1

echo -e "${cyan}******************************************************************************${clear}"
echo

echo -n "Verifying Dfinity Canister SDK (DFX) ..."

# verify and log canister sdk status on user's system
dfx_location="$(which dfx)"
dfx_version="$(dfx --version)"
dfx_version_numeric="$(echo $dfx_version | sed 's/[^0-9]*//g')"

echo "DFX version ${dfx_version} @ ${dfx_location}" >> "${dfx_build_log}"

# here we can try to guide folks through dfx canister sdk install, if they don't have it.
# note that this can be rocky depending on both client- and server-side wrinkles.
# user may find manual SDK install to be the best path, after which this will run smoothly.
if [ -z "$dfx_location" ]
then
  echo -e "${red}ICPipeline cannot detect the Dfinity Canister SDK (dfx) on your system.${clear}"
  echo "This setup requires the SDK, and we can try to install it for you now."
  echo "However, please don't be discouraged if you need to exit,"
  echo "install the SDK, and then re-run the installer."
  echo "Should we go ahead and try to install the Canister SDK now?"
  echo
  read -p "Install Canister SDK? (enter \"YES\" to install): " install_canister_sdk
  install_canister_sdk=${install_canister_sdk:-'NO'} && install_canister_sdk=$(echo "${install_canister_sdk}" | tr 'A-Z' 'a-z')

  if [[ "yes" == "${install_canister_sdk}" ]]
  then
    sh +m -ci "$(curl -fsSL https://sdk.dfinity.org/install.sh)"
    echo "Canister SDK successfully installed by the ICPipeline installer." >> "${dfx_build_log}"
  fi

  # try setting vars again after sdk install
  dfx_location="$(which dfx)"
  dfx_version="$(dfx --version)"

  if [ ! -z "$dfx_location" ]
  then
    echo -e "${green}Canister SDK installation successful, proceeding with ICPipeline installation.${clear}"
  else
    echo -e "${red}The installer was unable to complete Canister SDK installation.${clear}"
    echo -e "Please consult ${magenta}Dfinity's${clear} authoritative documentation to install the SDK:"
    echo
    echo "https://sdk.dfinity.org/"
    echo
    echo "Installer will exit now.  Please retry after completing SDK installation."
    system_checks_ok=false
    exit_on_err "Canister SDK not found and/or SDK installation failed."
  fi
fi


if [ ! $dfx_version_numeric -ge 084 ]; then

  echo
  echo -e "${yellow}It seems you're running an older version of the Dfinity Canister SDK (DFX).${clear}"
  echo
  echo "In order to run smoothly in all phases, ICPipeline calls for SDK version 0.8.4 or greater."
  echo
  echo "Upgrading the SDK is easy.  You can refer to Dfinity documentation for the step-by-step:"
  echo "https://sdk.dfinity.org/"
  echo
  echo "The installer will exit now.  Please run the installer again after upgrading the Canister SDK."
  sleep 3

fi
sleep 1
echo -en " "
greencheck
sleep 1

echo -e "${cyan}******************************************************************************${clear}"
echo

echo -en "Verifying your ${magenta}DFX Identity${clear} ... "

# verify dfx identity, and that the identity has a cycles wallet
dfx_identity=$(cd ./manager${git_repo_suffix} && dfx identity --network ic whoami)
dfx_wallet=$(cd ./manager${git_repo_suffix} && dfx identity --network ic get-wallet)

#  this one, unless i'm missing something, would be real corner case, but here goes ...
if [[ "${#dfx_identity}" -gt 0 ]]
then
  
  sleep .5
  echo -en "${graylight}${dfx_identity}${clear} "
  sleep .5
  greencheck
  sleep 1

else
  echo -e "${red}Error: the installer is unable to detect the user's DFX Identity.${clear}"
  echo "Seems odd that we even got this far ..."
  echo "In any case, the installer must exit now.  Please try ${cyan}ICPipeline${clear} again when your ${magenta}DFX Identity${clear} is in order."
  # log this unfortunate event
  echo "Installer exited early: did not detect user's DFX Identity." >> "${dfx_build_log}"
  system_checks_ok=false
  exit_on_err "DFX Identity not found."
fi

echo -e "${cyan}******************************************************************************${clear}"
echo

echo -n "Verifying your Cycles Wallet ... "

# this case (where the user has a dfx identity, but no wallet) is more likely in the wild.
# not the most rigorous of checks ... just verifying that there's something, anything, for a wallet.
# but it is coming straight from the horse's mouth, so it should be valid or nothing.
if [[ "${#dfx_wallet}" -gt 0 ]]
then
  
  sleep .5
  echo -en "${graylight}${dfx_wallet}${clear} "
  sleep .5
  greencheck
  sleep 1

else
  echo "${red}ERROR: UNFORTUNATELY, WE'VE ENCOUNTERED A (just temporary) SHOW STOPPER.${clear}"
  echo
  echo -e "The installer is unable to detect a ${graylight}cycles wallet${clear} for your current ${magenta}DFX Identity${clear}, ${graylight}${dfx_identity}${clear}."
  echo
  echo -e "To complete your ${cyan}ICPipeline${clear} installation, you need to be using a ${magenta}DFX Identity${clear} with an assigned ${graylight}cycles wallet${clear}."
  echo "Your wallet will also need to have a sufficient ${graylight}cycles balance${clear}, and we'll be verifying that too."
  echo
  echo "However, it seems that your current ${magenta}DFX Identity${clear} does not have an assigned ${graylight}cycles wallet${clear} at all."
  echo "This is something you'll need to rectify before proceeding with your ${cyan}ICPipeline${clear} installation."
  echo
  echo "These resources should help."
  echo "For the lowdown on ${magenta}DFX Identity${clear}:"
  echo "---> https://smartcontracts.org/docs/developers-guide/cli-reference/dfx-identity.html"
  echo "... and on wallets and cycles:"
  echo "---> https://smartcontracts.org/docs/developers-guide/cli-reference/dfx-wallet.html"
  echo -e "The installer will exit now.  Please try ${cyan}ICPipeline${clear} again once you get your ${magenta}DFX Identity${clear} and ${graylight}cycles wallet${clear} squared away.  Thanks."
    # log this
  echo "Early installer exit: did not detect cycles wallet associated with user's DFX Identity." >> "${dfx_build_log}"
  system_checks_ok=false
  exit_on_err "DFX user has no cycles wallet."
fi

echo -e "${cyan}******************************************************************************${clear}"
echo

echo -n "Verifying JQ ... "

jq_location="$(which jq)"
jq_version="$(jq --version)"

# install is cake but user should handle it...brew update first, etc.
if [ -z "$jq_location" ]
then

  echo "We seem to be missing JQ, and we will need that for parsing some JSON items."
  echo "To install JQ, just \"brew install jq\"."
  echo "It's better if you do it yourself, so you can brew update first, etc."
  echo
  echo "The installer will exit now.  Please try again after installing JQ."
  system_checks_ok=false
  exit_on_err "JQ not found on system."

else

  sleep .5
  echo -en "JQ version ${jq_version} ... "
  sleep .5
  greencheck
  sleep 1

fi

echo -e "${cyan}******************************************************************************${clear}"
echo

echo -n "Verifying Git ... "

git_location="$(which git)"
git_version="$(git --version)"

if [ -z "$git_location" ]
then

  echo "Not sure how we made it this far without Git, but the installer can't detect it now."
  echo "Git is necessary to complete your ICPipeline installation."
  echo "The installer will exit now.  Please try again after installing Git on your system."
  system_checks_ok=false
  exit_on_err "Git not found on system."

else

  sleep .5
  echo -en "${git_version} ... "
  sleep .5
  greencheck
  sleep 1

fi

echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

if [[ true == ${system_checks_ok} ]]
then

  echo -en "${green}Your system seems to be in good order to install ICPipeline ... ${clear}"
  greencheck
  echo
  echo -e "${green}Proceeding with your installation.${clear}"
  echo
  echo -e "${cyan}******************************************************************************${clear}"
  echo

fi

# ****************************************************************************
# Requirements verifications complete, proceeding to user-configurable options
# ****************************************************************************

# ***********************************
# handle user input github auth token
# ***********************************
echo "Please enter a valid Github auth token for the GitHub account containing"
echo -e "the ${magenta}Internet Computer${clear} project repos that you'll deploy with ${cyan}ICPipeline${clear}."
echo -e "Your ${cyan}Workers${clear} will use this token for secure access to your private Github repos."
echo
echo "Alternatively, if you intend to deploy only from public Git repositories, just press <ENTER> to skip this."
echo

# User supplied GitHub auth token for authenticated fetching of their IC projects into the framework.
# Validation as follows: user can skip the token altogether, though we'll ask them to confirm so everyone's on the same page.
# Not sure if this might seem ... untrusty, to some folks.  And if they do add a token we'll validate it as >= 40-char length,
# of which first two chars are "gh...", which matches all current GH token formats.
isgood=0
while [[ $isgood == 0 ]]; do
  # Reset eval vars at top of each loop
  gh_auth_token=""
  skip_gh_token=""
  
  while true; do

    read -p "GitHub Auth Token: " gh_auth_token
    echo
    read -p "Confirm GitHub Auth Token: " gh_auth_token2
    echo

    [ "${gh_auth_token}" = "${gh_auth_token2}" ] && break || echo "Auth tokens do not match, let's try again."
  
  done # End while password/pw-confirm entries do not match

  while [[ ! ${#gh_auth_token} -gt 0 && ( ! ${skip_gh_token} = "yes" && ! ${skip_gh_token} = "token" ) ]]; do
    echo
    echo -e "${cyan}******************************************************************************${clear}"
    echo
    echo "This is just to confirm that you don't wish to enter a GitHub auth token.  If you don't enter one,"
    echo "you'll able to deploy only public GitHub repos with ICPipeline."
    echo
    echo "It's fine if you prefer to do public repos only.  We're just checking so it works the way you expect."
    echo
    echo -e "${cyan}******************************************************************************${clear}"
    echo
    # Ask user to type "token" for a redo
    read -p "Press <ENTER> to skip token and proceed.  Or type and enter \"TOKEN\" to enter a GitHub auth token: " skip_gh_token
    skip_gh_token=${skip_gh_token:-'YES'} && skip_gh_token=$(echo "${skip_gh_token}" | tr 'A-Z' 'a-z')
    
    # Remain in this loop 'til we have valid yes/no (i.e. "token") on token skip ...
    while [[ ! ${skip_gh_token} == "yes" && ! ${skip_gh_token} == "token" ]]; do invalid_response; done
    # Once user has confirmed skip token we can jump ahead a bit
    if [[ "${skip_gh_token}" == "yes" ]]; then isgood=1; break 2; fi

  done # End while confirming user's intent to skip gh token

  # Remaining stuff is n/a if we're skipping the token
  if [[ ${#gh_auth_token} -gt 0 ]]; then

    # Validating gh token for the newer oauth format ... with some reservations.
    # This topic has some profile in the user auth realm, so we'll try to do our bit until we get yelled at.
    while [[ ! ${gh_auth_token::2} == "gh" || ${#gh_auth_token} -lt 40 ]]; do
      echo
      echo -e "${cyan}******************************************************************************${clear}"
      echo
      echo -e "${yellow}Are you quite sure?  You entered \"${gh_auth_token}\", which doesn't seem to be a valid GitHub auth token.${clear}"
      echo
      echo "In GitHub's current format, a valid token should be a 40-character string starting with \"gh...\"."
      echo
      echo "If you're using an older-format token, a new one is easy to create.  FYI:"
      echo
      echo "https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token"
      echo
      echo "We recommend a dedicated token for this anyway, which you can revoke easily."
      echo
      echo "If you think this is overly stringent, or causing false hits on valid tokens, kindly let us know.  Thanks."
      echo
      echo -e "${cyan}******************************************************************************${clear}"
      echo
      break
    done # End while token failing validation
    
    if [[ ${gh_auth_token::2} == "gh" && ! ${#gh_auth_token} -lt 40 ]]; then isgood=1; fi

  fi # End if token length > 0

done # End while validating GH auth token entry

# When GH token is past the gauntlet, write it to .env
echo -n "GITHUB_AUTH_TOKEN=${gh_auth_token}" | xargs >> "${dotenv_file}"

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

# *******************************************************************************************
# Handle user options for enable/disable worker password auth, password setup (if applicable)
# *******************************************************************************************

# In all cases (i.e. whether or not user opts to disable password auth), we generate a key pair for key-based ssh auth on Workers.
# the public key goes into the docker build whence docker setup injects it into authorized_keys on each container.
# Worker ssh access is via the private key from this pair; installer parks the private key in /resources/worker-ssh-key/
# Later on we offer to cp it to user's home ~/.ssh (at user's option).

# Use ed25519 pk algo by default
ssh-keygen -t ed25519 -f ./${worker_ssh_keyfile_name} -q -N ""

# ...or rsa works fine -- marginally less secure and longer key length, but theoretically more backward-compatible.
# (can't recall ed25519 being too bleeding-edge for anything in real life)
# ssh-keygen -t rsa -b 4096 -f ./${worker_ssh_keyfile_name} -q -N ""

# Copy public keyfile into docker build
cp ./${worker_ssh_keyfile_name}.pub "${icpw_dir}"/${worker_ssh_keyfile_name}.pub
# Copy private key into /resources/worker-ssh-key
cp ./"${worker_ssh_keyfile_name}" "${resources_dir}"/worker-ssh-key/"${worker_ssh_keyfile_name}"
# Clean up after
rm -f ./"${worker_ssh_keyfile_name}" ./"${worker_ssh_keyfile_name}".pub

# This deals with the icpipeline OS system user on every ICPipeline Worker container.  They run Ubuntu.  This user is
# basically the big cheese.  Worker's brains all run in /home/icpipeline, the user basically owns everything that root
# doesn't absolutely have to, she has passwordless sudo all.  I think we mention elsewhere that curtailing icpipeline's
# privileges will very likely break stuff, because everything.
echo -e "Each containerized ${cyan}ICPipeline Worker${clear}/replica has an \"icpipeline\" system admin user."
echo -e "${graylight}Be aware that this system user has full, passwordless sudo su privileges on each Worker.${clear}"
echo
echo -e "Note that key-based authentication is always enabled on your ${cyan}Workers${clear}."
echo
echo "The installer will generate an SSH key pair."
echo " --> The public key is written to each Worker's authorized_keys config file."
echo " --> The private key is placed in /resources/worker-ssh-key/.  Share with care."
echo
echo "We suggest disabling password authentication as a best practice, and that's the default setting."
echo
echo "But you can optionally enable password auth if it suits your requirements."
echo

echo "Just press <ENTER> to accept the default setting (passwords disabled), and skip to the next option."
echo
echo -e "${yellow}To be clear: pressing <ENTER> will disable password authentication on all your ICPipeline Workers${clear}."
echo -e "We're generating a key pair and you'll use that private key to log into your ${cyan}Workers${clear}."
echo
echo -e "OR type and enter \"ENABLE\" to allow password authentication on your ${cyan}Workers${clear},"
echo "and create a password for use when logging into them."
echo

isgood=0
while [[ $isgood == 0 ]]; do
  echo
  read -p "Enable password authentication? (type and enter \"ENABLE\", or press <ENTER> to disable): " enable_password_auth
  enable_password_auth=${enable_password_auth:-'NO'} && enable_password_auth=$(echo "${enable_password_auth}" | tr 'A-Z' 'a-z')
  while [[ ! ${enable_password_auth} == "no" && ! ${enable_password_auth} == "enable" ]]; do invalid_response; done
  if [[ ${enable_password_auth} == "no" ||  ${enable_password_auth} == "enable" ]]; then isgood=1; fi
done

if [[ "enable" == "${enable_password_auth}" ]]
then
  echo -n "DISABLE_PW_AUTH=false" | xargs >> "${dotenv_file}"
  echo
  echo "No problem.  Your Workers will have password authentication enabled."
  echo
  echo -e "Please assign a password for the \"icpipeline\" admin system user on your ${cyan}ICPipeline Workers${clear}."
  echo

  # Keeping password requirements to a bare minimum, merely a 6-char min length.
  # We did this to reduce onboarding friction for tire-kickers, whom we regard as crucial to our project's prospects.
  # But in a framework doing real work, these nodes shouldn't have password auth at all, much less with a joke of a password.
  while true; do
    len=0
    while [ $len -lt 6 ]; do
      read -s -p "Password: " icpw_user_pw
      echo
      len=${#icpw_user_pw}
      if [ ${len} -lt 6 ]
      then
        echo "Password must be at least six characters in length, please try again."
      fi
    done
    read -s -p "Confirm Password: " icpw_user_pw2
    echo
    [ "${icpw_user_pw}" = "${icpw_user_pw2}" ] && break || echo "Passwords do not match, please try again."
  done

else
  echo -n "DISABLE_PW_AUTH=true" | xargs >> "${dotenv_file}"
  icpw_user_pw="password_auth_disabled"
fi

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

# ************************************************************
# Handle user input local configuration of worker access ports
# ************************************************************

# Initialize a file to hold input'd ports  (may end up being just a log...tbd).
# touch "${resources_dir}"/worker_ingress_port_list.conf
# include default ports 22 and 8080 in array (will scrub redundant user entries if they occur)
default_ingress_ports_array=(22 8080 65000 8090)
ingress_ports_array=${default_ingress_ports_array[*]}

echo -e "${yellow}IMPORTANT: Please take a moment to review this >>>${clear}"
echo
echo -e "By default, ${cyan}ICPipeline${clear} configures your ${cyan}Workers${clear} for remote access on just two network ports:"
echo
echo -e "--> ${green}Port 22${clear} (to allow for remote/SSH Worker access)"
echo -e "--> ${green}Port 8080${clear} (enabling browser access to d'apps deployed on Worker replica hosts)"
echo -e "--> ${green}Port 8090${clear} (used by Workers enabled for Internet Identity)"
echo -e "--> ${green}Port 65000${clear} (for browser-based SSH access to Workers so enabled)"
echo
echo -e "This applies in both ${graylight}Public${clear} and ${graylight}Private${clear} Network Modes."
echo
echo "Your IC project(s) -- or perhaps other factors specific to your environment -- may require additional open ports."
echo "If so, this is where you configure them."
echo
echo "Note that these port configurations all live in a single AWS security group (tagged \"ICPipeline Worker Security Group\"),"
echo -e "which is applied to all your ${cyan}Worker${clear} containers.  So you can always make additional tweaks directly"
echo "via the AWS console or CLI."
echo
echo "If you make a mistake, no problem.  You can just <CONTROL-D> to back out and start your port list over."
echo
echo "If we have failed in our efforts to make this not-confusing, you may want to touch base with a systems"
echo -e "or network person on your team.  Or reach out to ${cyan}ICPipeline${clear} for assistance."
echo

isgood=0
while [[ $isgood == 0 ]]; do

  echo
  read -p "Enable Worker access on additional ports? (type and enter \"PORTS\", or press <ENTER> to skip): " add_ports
  add_ports=${add_ports:-'NO'} && add_ports=$(echo "${add_ports}" | tr 'A-Z' 'a-z')

  while [[ ! ${add_ports} == "no" && ! ${add_ports} == "ports" ]]; do invalid_response; done
  if [[ ${add_ports} == "no" ||  ${add_ports} == "ports" ]]; then isgood=1; fi

done

if [[ "ports" == "${add_ports}" ]]
then

  while true; do

    # reset ingress ports array to defaults on each user retry
    # ingress_ports_array=(22 8080 65000 8090)
    
   

    echo "Enter your required ingress port numbers, one at a time, and press <ENTER> after each one."
    echo
    echo "Then <CONTROL+D> when you're done adding ports."
    echo
    echo "We'll review and confirm your ports list before it's final."
    echo
    echo "Enter port numbers (One at a time, <ENTER> after each one, <CONTROL-D> when complete):"

    while read ingress_port
    do
      
      [[ "$ingress_port" =~ $valid_port_regex ]] && ingress_ports_array=( "${ingress_ports_array[@]}" "${ingress_port}" ) || echo "That's not a valid port number, please try again."
    
    done

    # scrub duplicates from input'd port list
    ingress_ports_unique=( $(tr ' ' '\n' <<<"${ingress_ports_array[@]}" | awk '!u[$0]++' | tr '\n' ' ') )

    # write deduped ports list to file
    # printf "%s\n" "${ingress_ports_unique[@]}" >> "${resources_dir}"/worker_ingress_port_list.conf

    echo
    echo "Thank you.  Here's your complete list of authorized ingress ports (duplicates removed, default ports 22 and 8080 included):"

    for tcp_port in "${ingress_ports_unique[@]}"
    do
      echo "Port ${tcp_port}"
    done

      # set exit condition flag
      incomplete=true

      while $incomplete
      do
        
        echo "Is this the correct access port list for your Workers?"
        echo
        echo "Press <ENTER> to accept and confirm this port list.  Or type and enter \"AGAIN\" to start over and try again."
        echo

        read isdone norton

        # to-lowercase user input for compare
        isdone=$(echo $isdone | tr 'A-Z' 'a-z')

        if [ ! "$isdone" = "again" ]
        then

          echo
          echo -e "Thank you.  Your ${cyan}Workers${clear} will accept inbound connections on these ports:"
          # exit loop from two-deep
          break 2
        else
          # back to the top
          incomplete=false
          # Reset ingress ports array back to defaults on each re-do
          ingress_ports_array=(${default_ingress_ports_array[*]})
        fi
      
      done
  done

  for tcp_port in "${ingress_ports_unique[@]}"
  do
    echo "Port ${tcp_port}"
  done
  echo

fi

# ingress ports array now complete, dedupe in case user has re-added default ports or typed any repeats
ingress_ports_unique=( $(tr ' ' '\n' <<<"${ingress_ports_array[@]}" | awk '!u[$0]++' | tr '\n' ' ') )

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

# # *************************************************************
# # handle user input of how many workers installer should create
# # *************************************************************
# echo -e "The installer will create two containerized ${cyan}Workers${clear} by default."
# echo
# echo -e "Each ${cyan}Worker${clear} will automatically connect and register with your ${cyan}Pipeline Manager${clear} d'app."
# echo
# echo -e "We opted for two ${cyan}Workers${clear} as the default, in order to provide a good sense of how the platform works."
# echo
# echo -e "A single ${cyan}Worker${clear} will do just fine -- or create as many as you like."
# echo -e "You can always add more, ${cyan}Workers${clear} are ephemeral and replaceable."
# echo
# echo -e "Please enter the number of ${cyan}Workers${clear} (from 1 to 9) that you'd like to start with."

# while true; do
#   read -p "Number of Workers (<ENTER> for default 2): " number_of_workers
#   number_of_workers=${number_of_workers:-2}
#   echo
#   [[ "${number_of_workers}" =~ ^[0-9]{1}$ ]] && break || echo "You did not enter a number between 1 and 9, please try again."
# done
# echo "Thank you. The number of the counting shall be ${number_of_workers}."

# echo
# echo -e "${cyan}******************************************************************************"
# echo -e "******************************************************************************${clear}"
# echo

# # these brief sleeps are mostly discretionary, to smooth out the workflow,
# # allow users to read and follow along better, etc.
# sleep 4


# *************************************************************************************************
# This is where bring in the main component modules, like so:
#   First ICPM build/deploy to IC.
#   Then AWS networking and container buildout.
#   -- If user chooses VPN option, the VPN module is called directly from the network module.
#   Then the container module for Docker stuff.
#    -- in Private Network Mode only, user may select Fargate or ECS/EC2 container infra. 
# *************************************************************************************************

# To this point, no non-local changes have occurred at all.  Other than remnants of some logging,
# there's nothing crucial to undo for kill/re-run at this point.  If you do, it won't hurt to do a quick sweep with
# the resetter; that will start your logs clean, etc for another go.

# This module stands up the network scaffolding in AWS cloud for hosting worker containers.
# It builds an "ICPipeline VPC" with one or two subnets depending on user preference.
#  Here it takes "include" as an arg, denoting that it's sourced by the installer.  It can also be run standalone.
source ${resources_dir}/include/create_network_infra_aws.sh include || exit_on_err "AWS infrastructure module not found, please check your project directory structure."

# Flow is contiguous between modules here ...
echo
echo "Installer workflow now transitions straight to the ICPM module ..."
echo

# This module builds and deploys the Manager d'app to the IC.
source ${resources_dir}/include/create_icpm_dapp_ic.sh || exit_on_err "Canister deployment module not found, please check your project directory structure."

# Our worker.config.env file is fully compiled at this point, complete for copy into the Worker Docker build module.
cp -f "${dotenv_file}" "${icpw_dir}"|| exit_on_err "Installer encountered a problem copying worker.config.env into Docker build."

# Engage user to offer the choice of Fargate vs ECS/EC2 container infrastructure (Because AWS constraints, this option is Private Network Mode-only).
if [[ true == ${private_network_mode} ]]; then

  if [[ "fargate" == ${launch_mode_selection} ]]; then

    source ${resources_dir}/include/create_container_infra_aws.sh include fargate || exit_on_err "AWS Container deployment module not found, please check your project directory structure."
  
  elif [[ "ec2" == ${launch_mode_selection} ]]; then
    
    source ${resources_dir}/include/create_container_infra_aws.sh include ec2 iam || exit_on_err "AWS Container deployment module not found, please check your project directory structure."
  
  fi

elif [[ true == ${public_network_mode} ]]; then

  echo -e "The installer will now build, push and run your ${cyan}ICPipeline Workers${clear} on AWS Fargate."
  echo
  sleep 3
  # And just the one if Public Network Mode (because only Fargate supports public IPs)
  source ${resources_dir}/include/create_container_infra_aws.sh include fargate || exit_on_err "AWS Container deployment module not found, please check your project directory structure."

fi

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

if [[ "no" == "${enable_password_auth}" ]]
then

  echo -e "You wisely chose to disable password authentication on your ${cyan}Worker${clear} containers."

else

  echo -e "${yellow}You opted to leave password authentication enabled on your Workers${clear}."
  echo -e "That's fine, and just a reminder that key-based auth is configured on each ${cyan}Worker${clear} as well."

fi

if [[ "yes" == "${copy_ssh_key}" ]]
then
  cp -f ${resources_dir}/worker-ssh-key/${worker_ssh_keyfile_name} ~/.ssh/${worker_ssh_keyfile_name} && chmod 0400 ~/.ssh/${worker_ssh_keyfile_name}

  echo
  if [[ -f ~/.ssh/${worker_ssh_keyfile_name} ]]
  then
    echo -e "${green}Worker SSH key successfully copied to ~/.ssh/${worker_ssh_keyfile_name}${clear}"
    echo "... also set its permissions for a private key file (0400)."
  else
    echo "Installer was unable to copy Worker SSH key."
    echo "Perhaps something relating to permissions and your shell setup...?"
    echo "Anyway, not a problem.  Just copy the key file manually, or use it from its present location (${resources_dir}/worker-ssh-key/${worker_ssh_keyfile_name})."
  fi
  echo
fi

# reverse the order of the lines in our aws resetter script -- so deletes go last-in-first-out.
# ...appending so we don't scrub the shebang header
tac "${aws_resetter_script_reverse}" >> "${aws_resetter_script}"
# and make it executable
chmod +x "${aws_resetter_script_reverse}"

echo -e "ICPipeline installation is complete.  The ${cyan}ICPipeline${clear} team appreciates your participation."
echo
echo "It is worthwhile to read through this information relating to your installation."
echo
echo -e "${cyan}Your Pipeline Manager interface will give you full access and control of the ${number_of_workers} Worker containers we just created.${clear}"
echo
echo -e "Please note that your ${cyan}Worker${clear} containers have some bootstrap tasks to complete on initialization."
echo "It is somewhat more involved than the usual \"docker run\", and it takes just a minute or two."
echo -e "So, you can log into your ${cyan}Pipeline Manager${clear} right away, but there might be just a brief delay"
echo -e "before your registered ${cyan}Workers${clear} appear in your ${cyan}IPCM dashboard${clear}."
echo
echo -e "If you want to ${green}grab a beverage in the meantime${clear}, rigorous testing has shown that your return should be well-timed."
echo

if [[ "yes" == "${add_vpn}" ]]
then

  echo -e "${yellow}Also, as noted above, please be patient with your new AWS Client VPN Endpoint.  These endpoints just"
  echo -e "take a while to come up, and it does vary.${clear}"
  echo
  echo -e "You can check the AWS console (VPC --> Client VPN Endpoints) for the status of your VPN."
  echo
  echo -e "The endpoint's ${yellow}\"Pending-associate\"${clear} state will change to ${green}\"Available\"${clear} when it's ready."
  echo
  echo "Sometimes they take so long that you'll think something must've gone wrong, but it's probably fine."
  echo
  echo "While waiting, you can import the client config file (in /resources/vpn-client-config-file) into an OpenVPN-based client."
  echo
  echo "If you've previously worked with AWS client config files, which require you to manually paste in the client certificate"
  echo "and key, that part is already taken care of."
  echo
  echo "Just import the .ovpn file as-is, and your tunnel should nail right up.  Routing and access rules are set up so you'll"
  echo "maintain Internet access, etc. while connected."
  echo
  echo "Your normal network access will not be routed through AWS (or anyplace else).  The VPN routes only your internally-addressed"
  echo "packets, leaving everything else alone."
  echo
  echo -e "${green}Note that this delay on the VPN endpoint doesn't prevent you from using ICPipeline.  The delay only affects"
  echo -e "remote SSH access into your Workers, which is not even necessary in most regular workflows.  Your ICPipeline is up"
  echo -e "and fully accessible in the meantime.${clear}"
  echo

  sleep 4
  echo "To SSH into your private-networked Workers, follow these steps:"
  echo
  echo "--> Use any OpenVPN-based client to import the client config file we just created,"
  echo "    and connect to your new VPN."
  echo
  echo "--> Then, using the SSH key we also just created,"
  echo "--> refer to ICPM for the private IP address of any Worker,"
  echo "--> And connect like so:"
  echo "    ssh icpipeline@<your worker private ip address> -i <your worker ssh key>"
  echo

fi

echo "************************************************************************************************"
echo "************************************************************************************************"
echo "***** You can now log into your ICPipeline Manager on the Internet Computer blockchain at: *****"
echo -e "*********>>>     ${cyan}https://${assets_canister_id}.raw.ic0.app${clear}    <<<*************************"
echo "************************************************************************************************"
echo "**********    Feel free to touch base if we can assist you along the way:   ********************"
echo -e "********************>>>    ${cyan}support@icpipeline.com${clear}       <<<*************************************"
echo -e "********************>>>    ${cyan}Discord: https://discord.gg/FYR3kzKHYa${clear}     <<<***********************"
echo -e "********************>>>    ${cyan}Twitter: https://twitter.com/icpipeline${clear}   <<<************************"
echo "************************************************************************************************"
echo "************************************************************************************************"

echo
echo -e "We hope ${cyan}ICPipeline${clear} works for you.  Your interest and engagement will make it possible"
echo "for us execute the rest of the roadmap, which has quite a few good things in it."
echo
echo -e "${cyan}Team ICPipeline${clear} extends its thanks, and we're here to help if you need us."
