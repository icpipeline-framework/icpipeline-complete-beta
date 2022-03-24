#!/bin/bash

# note this script will break if run by itself;
# it is an include of the ICPipeline main installer.

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

echo "Welcome to your ICPM module."
echo "This module builds and deploys your ICPipeline Manager console d'app to the Internet Computer,"
echo "On completion, this module will rejoin the main installer workflow automatically."
echo
sleep 4

echo -e "Starting ${magenta}DFX${clear} activities."
echo -e "Installer will build and deploy your ${cyan}ICPipeline Manager${clear} canister d'app to the ${magenta}Internet Computer${clear}."

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

echo "Main project directory location on your system: ${project_home_dir}"
echo -e "${cyan}ICPipeline Manager${clear} subdirectory name: ${icpm_dir_name}"
echo "Full path to local ICPM build: ${icpm_dir}"

echo "You are running NodeJS version ${node_version}, with NPM version ${npm_version}"
echo "We strongly suggest using an even-numbered Node version ^16, with NPM version ^7."
echo "Please manage your Node and NPM versions accordingly for most predictable outcomes."

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

echo "Deploying canister d'apps to the Internet Computer requires cycles."
echo "Cycles are the blockchain gas of the Internet Computer blockchain."
echo "In order to complete this installation, you will need to have cycles in a wallet."
echo "Cycles measure in increments of 1T (or one trillion).  That sounds like a lot,"
echo "but 1T cycles cost only a dollar (USD) and change."

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

echo "Confirming your cycles wallet balance with the Internet Computer ..."
echo
echo "Creating and funding canisters requires ~4T (four trillion) cycles per canister,"
echo "including initialization fees."

# query IC for cycles balance in user's wallet,
# try to advise the user depending on their balance.
cycles_balance_str="$(cd "${icpm_dir}" && exec dfx wallet --network ic balance)"
cycles_balance=${cycles_balance_str//[^0-9]/}
cycles_balance_t=$((cycles_balance / 1000000000000))
cycles_balance_t_rounded=$(echo $cycles_balance_t | awk '{print int($1+0.5)}')
# echo "Your wallet's current cycles balance is ${cycles_balance}"

if (( "${cycles_balance}" <= 10000000000000 && "${cycles_balance}" >= 8000000000000 ))
then

  echo -e "${yellow}Your wallet's cycles balance of ${cycles_balance} (roughly ${cycles_balance_t_rounded}T) should suffice to"
  echo -e "complete your ICPM deployment, but you're running low.  You might consider adding some cycles to your wallet soon.${clear}"
  echo "A few USD worth is all it takes."
  echo
  echo "Info resources:"
  echo "https://smartcontracts.org/docs/developers-guide/default-wallet.html"
  echo "https://faucet.dfinity.org/"

elif (( "${cycles_balance}" < 8000000000000 ))
then
  
  echo -e "${red}Your wallet's cycles balance of ${cycles_balance} (roughly ${cycles_balance_t_rounded}T) is not enough"
  echo -e "to create and fund the two canisters required for your Pipeline Manager deployment.${clear}"
  echo "Please add some cycles to your wallet balance before re-running this installer."
  echo
  echo "You can find additional guidance here:"
  echo "https://smartcontracts.org/docs/developers-guide/default-wallet.html"
  echo
  echo "The Cycles Faucet may be of particular interest:"
  echo "https://faucet.dfinity.org/"
  echo
  # write a note to the log
  echo "Error: failed preliminary check with cycles balance of ${cycles_balance}" >> "${dfx_build_log}"
  exit 0

else

  echo
  echo -e "${green}Your cycles wallet balance of about ${cycles_balance_t_rounded}T (${cycles_balance} cycles) is more"
  echo -e "than enough for our two-canister deployment.  Moving right along with your ICPM build${clear}."

fi

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

# check for presence of a couple of items that *should* be screened by .gitignore, but just in case
# first the .dfx subdirectory, remove if necessary
if [ -d "${icpm_dir}/.dfx" ]
then
  rm -rf ${icpm_dir}/.dfx
else
   echo "${icpm_dir}/.dfx not detected, proceeding with install."
fi

#  now npm install and update, likewise in the proper location
echo "Starting NPM tasks."
echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo
echo -e "Running npm install for ${cyan}ICPipeline Manager${clear} build..."
echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

(cd "${icpm_dir}" && exec npm install 2>&1 >> "${npm_build_log}")

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

echo -e "Running npm update for ${cyan}ICPipeline Manager${clear} build..."

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

(cd "${icpm_dir}" && exec npm update 2>&1 >> "${npm_build_log}")

npm_invoked_err="$(cat ${npm_build_log} | grep -iF error)"
if [ ! -z "$npm_invoked_err" ]
then
  
  echo -e "${red}We encountered one or more errors in the npm build/update process."
  echo "This will likely cause problems farther along in the install process, so the"
  echo -e "installer will exit now.  Please try again once npm is able to build cleanly on your system.${clear}"
  exit 0

fi

echo -e "Now proceeding to ${magenta}DFX${clear} tasks."

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo
echo -e "Checking for stray ${magenta}DFX${clear} threads on host machine..."
(cd "${icpm_dir}" && exec killall dfx)
echo

# perform a clean/bg start dfx in the appropriate location
echo -e "Starting ${magenta}DFX${clear} clean, as a background thread..."

if (cd "${icpm_dir}" && exec dfx start --clean --background 2>&1 >> "${dfx_build_log}")
then
  
  echo
  echo -e "${cyan}******************************************************************************${clear}"
  echo
  echo -e "${green}DFX start is successful${clear}."
  echo
  echo -e "${cyan}******************************************************************************${clear}"

else

  echo -e "${red}ICPipeline is unable to start the DFX SDK on your system.${clear}"
  echo
  echo "The installer will exit now, so you can look into that.  Installing the"
  echo "Dfinity Canister SDK on your machine should do the trick."
  echo "You can refer to https://smartcontracts.org/docs/download.html"
  echo
  echo "It's very straightforward and reliable, so don't let it stand in your way!"
  echo "The installer will exit now.  Feel free to reach out if you think we can help."
  exit 1

fi

# dfx ping ic to verify connectivity
if (cd "${icpm_dir}" && exec dfx ping ic 2>&1 >> "${dfx_build_log}")
then
  
  echo
  echo -e "${green}DFX ping to the Internet Computer is successful.${clear}"
  echo

else

  echo -e "${yellow}DFX was unable to ping the Internet Computer via its native ICP protocol.${clear}"
  echo
  echo "This may be due to a network connectivity issue, on your end, or perhaps somewhere upstream."
  echo "Likewise, the IC itself can incur momentary blips, though those happen rarely."
  echo
  echo "The Internet happens, to the best of us."
  echo "The installer will exit now.  As a next step, we'd suggest just giving it another try."
  exit 1

fi

echo -e "${cyan}******************************************************************************${clear}"
echo
echo -e "Creating canisters on the ${magenta}Internet Computer${clear} for your ${cyan}ICPipeline Manager${clear}..."
echo

# Store user's current DFX_VERSION env var (if any, which is rare) so we can leave it as we found it.
# Then temporarily set DFX_VERSION env var to 0.8.4
dfx_version_save=$(echo $DFX_VERSION) && export DFX_VERSION=0.8.4

# (cd "${icpm_dir}" && exec dfx canister create --all 2>&1 | tee -a "${dfx_build_log}" && sleep .1)
echo -e "Running ${magenta}DFX${clear} build and deploy of ${cyan}Pipeline Manager${clear} code to new ${magenta}Internet Computer${clear} canisters."
echo

(cd "${icpm_dir}" && exec dfx deploy --network ic 2>&1 | tee -a "${dfx_build_log}" && sleep .1)

# Restore DFX_VERSION var to its original state after dfx execution.
export DFX_VERSION=${dfx_version_save}

# Extract canister ids from the canister_ids.json file just generated by dfx build.
data_canister_id=$(jq -r '.icpm.ic' ${icpm_dir}/canister_ids.json)
assets_canister_id=$(jq -r '.icpm_assets.ic' ${icpm_dir}/canister_ids.json)
echo "Pipeline Manager data canister ID: ${data_canister_id}"
echo "Pipeline Manager assets canister ID: ${assets_canister_id}"

echo -n "ICPM_CANISTER_ID=$data_canister_id" | xargs >> "${dotenv_file}"
echo -n "ICPM_ASSETS_CANISTER_ID=$assets_canister_id" | xargs >> "${dotenv_file}"

if (cd "${icpm_dir}" && exec killall dfx)
then

  echo -e "${magenta}DFX${clear} process complete."

fi

# We simply parse dfx.build.log file for occurrences of "error".  If "error" occurs anywhere in that log file, we will:
# Attempt to roll back any lingering IC artifacts;
# Message guidance to the user;
# Exit, leaving a clean environment for retry.
# dfx_invoked_err="$(cat ${dfx_build_log} | grep -iF error)"

# if [ ! -z "$dfx_invoked_err" ]
# then

#   echo -e "${red}Unfortunately, we are not passing all system checks required at this stage of the install process."
#   echo -e "We detected one or more errors in DFX output, which may need attention before we proceed.${clear}"
#   echo
#   echo "Before exiting, the installer will try to roll back what we've done to this point,"
#   echo "in order to leave you with a clean slate for re-try."
#   echo
#   echo "The IC occasionally incurs communications blips, and that may have happened here."
#   echo
#   echo "You can refer to ICPipeline documentation, and to Dfinity docs."
#   echo "You can also reach out to us and we'll try to help."

#   # Here we try to guide user through choice of whether to delete their ICPM canisters on the IC.
#   # This is a little tricky because:
#   #  A) It can be unclear at this point precisely what has gone wrong, or whether such canisters even exist; and
#   #  B) In partial/fragmented installation situations, delete will be the right choice 99/100 times.
#   #     But there's the edge case where deletion could blow away a canister holding actual data.
#   #     And losing the folks' data is just not what we are about.
#   echo -e "${yellow}This is a confirmation check, before we stop and delete"
#   echo "any canisters that may have been initialized on the Internet Computer during this partial install."
#   echo "If this is your first go at installing ICPipeline, then you should go ahead and confirm delete."
#   echo "This is just a safeguard against the possibility that your Pipeline Manager"
#   echo "is already up and running, with valuable data onboard, in which case deleting could place that data"
#   echo "at risk.  You are running this installer, so it's unlikely that this scenario applies in your case.  We just don't want to"
#   echo -e "take any chances with your data.${clear}"
#   echo "******************************************************************************"
#   echo "Shall we go ahead and \"clean the slate\" for another try at installing ICPipeline?"
#   read -p "Delete canisters? (enter \"YES\" to delete): " delete_ic_canisters
#   delete_ic_canisters=${delete_ic_canisters:-'NO'} && delete_ic_canisters=$(echo "${delete_ic_canisters}" | tr 'A-Z' 'a-z')

#   if [[ "yes" == "${delete_ic_canisters}" ]]
#   then

#     echo "Thank you.  Proceeding with stop/delete of remnant canisters..."
#     echo "Stopping canister ${data_canister_id}..."
#     (cd "${icpm_dir}" && exec dfx canister --network ic stop "${data_canister_id}")
#     echo "Deleting canister ${data_canister_id}..."
#     (cd "${icpm_dir}" && exec dfx canister --network ic delete "${data_canister_id}")
#     echo "Stopping canister ${assets_canister_id}..."
#     (cd "${icpm_dir}" && exec dfx canister --network ic stop "${assets_canister_id}")
#     echo "Deleting canister ${assets_canister_id}..."
#     (cd "${icpm_dir}" && exec dfx canister --network ic delete "${assets_canister_id}")
#     echo "ICPM module will exit now."
#     killall dfx
#     exit

#   else

#     echo "You did not enter \"YES\", so we will play it safe by NOT deleting your canisters."
#     echo "You can remove these canisters manually by running the following commands from a terminal."
#     echo "First, cd into ${icpm_dir_name}.  Then run these four commands in this order:"
#     echo "dfx canister --network ic stop ${data_canister_id}"
#     echo "dfx canister --network ic delete ${data_canister_id}"
#     echo "dfx canister --network ic stop ${assets_canister_id}"
#     echo "dfx canister --network ic delete ${assets_canister_id}"

#   fi

# fi

# NOTE: the above check (parsing for any occurrence[s] of "error" in our dfx build log)
# is replaced the following responsiveness check -- i.e. a real call to the live ICPM

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

echo
echo "Installer is running a health check on your ICPM dApp before we proceed with framework installation ..."
echo

icpm_favicon_uri="https://${assets_canister_id}.raw.ic0.app/favicon.ico"

icpm_isresponsive=$( ( wget ${icpm_favicon_uri} 2> /dev/null && echo true && rm -f favicon.ico ) || echo false )

# If we have no response from a simple request to ICPM ...
if [[ false == "${icpm_isresponsive}"  ]]; then

  echo "Unfortunately we are unable to communicate with ICPM ... and that's not good."
  echo
  echo -e "${yellow}This is to confirm with you, before we go ahead and try to roll back any canisters"
  echo -e "which may have been initialized on the Internet Computer during this incomplete ICPM deployment."
  echo -e "If this is your first try at installing ICPipeline, then you should go ahead and confirm for deletion."
  echo
  echo -e "This is purely a safeguard against a corner case, i.e. the slight possibility that your Pipeline Manager"
  echo -e "is already up and running, with potentially-valuable data in its canister state.  In such rare cases, canister deletion"
  echo -e "would cause the loss of those data.  Since are running this installer, it's highly unlikely that"
  echo -e "this scenario applies to you.  We just don't want to take any chances with your data.${clear}"
  echo
  echo "******************************************************************************"
  echo
  echo "Shall we go ahead and \"clean the slate\" (hopefully for another try at installing ICPipeline)?"
  echo
  
  read -p "Delete canisters? (enter \"YES\" to delete): " delete_ic_canisters
  delete_ic_canisters=${delete_ic_canisters:-'NO'} && delete_ic_canisters=$(echo "${delete_ic_canisters}" | tr 'A-Z' 'a-z')

  if [[ "yes" == "${delete_ic_canisters}" ]]
  then

    echo "Thank you.  Proceeding with stop/delete of remnant canisters..."
    echo "Stopping canister ${data_canister_id}..."
    (cd "${icpm_dir}" && exec dfx canister --network ic stop "${data_canister_id}")
    echo "Deleting canister ${data_canister_id}..."
    (cd "${icpm_dir}" && exec dfx canister --network ic delete "${data_canister_id}")
    echo "Stopping canister ${assets_canister_id}..."
    (cd "${icpm_dir}" && exec dfx canister --network ic stop "${assets_canister_id}")
    echo "Deleting canister ${assets_canister_id}..."
    (cd "${icpm_dir}" && exec dfx canister --network ic delete "${assets_canister_id}")
    echo "The ICPM module will exit now."
    exit

  else

    echo "You did not enter \"YES\", so we will play it safe by NOT deleting your canisters."
    echo "You can remove these canisters manually by running the following commands from a terminal."
    echo "First, cd into ${icpm_dir_name}.  Then run these four commands in this order:"
    echo "dfx canister --network ic stop ${data_canister_id}"
    echo "dfx canister --network ic delete ${data_canister_id}"
    echo "dfx canister --network ic stop ${assets_canister_id}"
    echo "dfx canister --network ic delete ${assets_canister_id}"

  fi # end if user chose to remove artifact canister after unsuccessful ICPM build.

fi # End if error handling for an unresponsive ICPM

# If we do have a responsive ICPM, we share the good news and proceed.
[[ true == "${icpm_isresponsive}"  ]] && echo -e "${green}Success!  Your ICPM d'app is built, deployed and responsive on the Internet Computer${clear}." && echo && echo  "Now rejoining the main installer workflow in progress..."

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo
# Let the folks have a quick look at what just happened before we move on ...
sleep 4