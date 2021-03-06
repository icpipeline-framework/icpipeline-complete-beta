#!/bin/bash

# NOTE: RUNNING THIS SCRIPT WILL DEFINITELY DESTROY YOUR WORKING ICPIPELINE INSTALLATION.
# RUN THIS ONLY to prepare for a do-over installation, and after reading these notes.

# IN ORDER FOR THIS TO WORK CORRECTLY, RUN IT FROM ITS PRESENT LOCATION.
# We placed it here in /resources/util, out of the way ... ish, so it won't get run inadvertently.

# Step-by-step "reset" goes like so:
# >> run this script and follow the prompts.

# This script:
# 1). Directly removes local installer artifacts, rolling back your local icpipeline project directory to ready-to-run state.
# 2). Generates (and optionally runs) a second script that removes all traces of your ICPM d'app from the Internet Computer, stopping/removing the two canisters.
# 3). (optionally) executes a third script that was previously generated by the installer at runtime.  That script removes all AWS resources created by the installer.
# Whether,as we hope, you're setting up for a new ICPipeline installation, or if you just want to tie it off and move on, this is a useful thing.

# read in some breadcrumbs left by the installer:
# the installer and the reset must be executed by the same aws profile, or reset will break.
# we also need the name of the ecs cluster (to poll it for any leftover running containers before we destroy it).
# and we need the git "branch" (actually it's a repo) suffix var, so the code base is identical branch-to-branch
# while still avoiding submodule path hell. 
# Cheers again to asheroto on github for this improved approach.
export $(echo $(cat installation_vars.env | sed 's/#.*//g' | sed 's/\r//g' | xargs) | envsubst)

# set up paths with reference to project home (run this script from right here in its current location)
project_home_dir=$(cd ../.. && pwd)
resources_dir=${project_home_dir}/resources
archive_dir=${resources_dir}/archive
icpm_dir=${project_home_dir}/manager${INSTALLER_GIT_REPO_SUFFIX}
icpw_dir=${project_home_dir}/worker-docker${INSTALLER_GIT_REPO_SUFFIX}

aws_resetter=${resources_dir}/cloudconf/aws/reset_installation_aws.sh

# color-code some outputs, etc.
source ${resources_dir}/include/formatting.sh

# Suppresses pagination of verbose AWS CLI outputs.
export AWS_PAGER=""

echo
echo "Welcome to ICPipeline Reset."
echo
echo -e "${yellow}IF YOU HAVE A WORKING ICPIPELINE INSTALLATION THAT YOU WISH TO PRESERVE,"
echo -e "YOU SHOULD EXIT RIGHT NOW (CONTROL-C to exit).${clear}"
echo
echo "You should run reset in preparation to reinstall ICPipeline."
echo "(Or if, sadly, you just want your ICPipeline to go away, reset will serve for that as well.)"

if [[ ! "${AWS_PROFILE}" == "${INSTALLER_AWS_PROFILE}" ]]
then

  echo
  echo -e "${red}HARD STOP ENCOUNTERED: ICPIPELINE RESET MUST BE RUN USING THE AWS PROFILE USED DURING THIS INSTALLATION.${clear}"
  echo -e "${yellow}We're not trying to be difficult, it's not a made-up security protocol.  It's just necessary"
  echo -e "in order for reset to work correctly.  We're trying to save headaches, not create them ;)${clear}"
  echo
  echo "Here's what you can try, in descending order of preferability:"
  echo "--> First option: If AT ALL possible, please run reset using the same AWS_PROFILE that performed your original install."
  echo "--> Second option: Take the hands-on approach with your AWS and canister reset scripts, running the individual commands in a terminal."
  echo "    (Or just delete the AWS stuff in the console, using the reset script as your checklist, in order top-down.)"
  echo "--> Third option: If you get stuck, reach out to us at ICPipeline and we'll try to help."
  echo
  echo "Reset must exit now.  Assuming you have access to the correct profile, just run this command, right here in this same window:"
  echo
  echo "    export AWS_PROFILE=<aws_profile_used_during_install>"
  echo
  echo "...after which this resetter should function as expected."
  echo
  exit 1

else

  echo
  echo -e "${green}AWS_PROFILE matches the profile used during installation, reset can proceed.${clear}"
  echo
  echo -e "${green}Note that validation of your type-in options is case-neutral.  Lowercase works fine throughout.${clear}"

fi
echo
echo -e "Reset will remove all resources created by the ${cyan}ICPipeline${clear} installer, in this order:"
echo
echo "--> Your local ICPipeline project directory get rolled back to its original, pre-install state."
echo "--> Your ICPM canisters will be removed from the Internet Computer."
echo "--> All AWS resources created by the installer will be deleted from your account."
echo "    This part may ask for your input at key points.  AWS reset has quite a few moving pieces, and we approach it carefully."
echo
echo "You'll have the opportunity to confirm each section separately.  Installer logs and reset/manifest scripts"
echo "will be preserved (in /resources/archive)."
echo
echo "First we'll roll back your local project folder to its pre-install state.  Note that certain"
echo "locally-generated resources don't apply to every use case.  So there's no cause for concern if you see a few"
echo -e "${yellow}\"Reset did not detect ...\"${clear} messages during local reset."
echo
echo "Press <ENTER> when ready to proceed with local project folder reset.  Or <CONTROL-C> to exit the resetter now."

pauseforuser

echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

echo -e "Canister reset stops and removes the two canisters that were deployed on the ${magenta}Internet Computer${clear}"
echo "during this installation for your ICPM dApp."
echo
echo "Your canister resetter script is dynamically generated right now, by running this file.  We leave you the option"
echo "of running it separately at a later time, but that's really for edge cases.  If you're undoing an ICPipeline installation,"
echo "you'll probably want to go ahead and run it -- it's unlikely that you'd want to keep a canister dApp running that's not doing anything."
echo
echo -e "The ${magenta}Internet Computer${clear} will redeposit the unused cycles in these canisters into their originating wallet."
echo
echo "Reset will show your new cycles wallet balance, including the recovered cycles."
echo
echo "If you prefer to run canister reset at a later time, the script is located in your ICPM module directory."
echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo

echo "Generating your canister resetter script ..."

# Fetch in our two canister ids from canister_ids.json
icpm_canister_id=$(cat ${icpm_dir}/canister_ids.json | jq -r '.icpm.ic')
icpm_assets_canister_id=$(cat ${icpm_dir}/canister_ids.json | jq -r '.icpm_assets.ic')


f="${icpm_dir}/reset_installation_ic.sh"

touch ${f} && echo "#!/bin/bash" > ${f} && chmod +x ${f} && echo $'\n' >> ${f}


echo $'\n' >> ${f}
echo "echo \"Stopping data canister ${icpm_canister_id}...\"" >> ${f}
echo "dfx canister --network ic stop ${icpm_canister_id}" >> ${f}
echo "echo \"Deleting data canister ${icpm_canister_id}...\"" >> ${f}
echo "dfx canister --network ic delete ${icpm_canister_id}" >> ${f}
echo "echo \"Stopping assets canister ${icpm_assets_canister_id}...\"" >> ${f}
echo "dfx canister --network ic stop ${icpm_assets_canister_id}" >> ${f}
echo "echo \"Deleting assets canister ${icpm_assets_canister_id}...\"" >> ${f}
echo "dfx canister --network ic delete ${icpm_assets_canister_id}" >> ${f}
echo $'\n' >> ${f}
echo "echo" >> ${f}
echo "echo \"Canister calls have been executed.\"" >> ${f}
echo "echo" >> ${f}
echo "echo \"Now retrieving your update cycles wallet balance from the Internet Computer ...\"" >> ${f}
echo "echo" >> ${f}
echo "echo \"Et voila, your new cycles wallet balance is \$(dfx wallet --network ic balance).\"" >> ${f}
echo "echo" >> ${f}

if [[ -f "${f}" ]]
then

  echo -e "${green}Canister resetter successfully generated.${clear}"
  echo
  echo "Reset will check back to see if you want to run it from here."

else

  echo "Unable to locate canister reset script."
  echo "Canister removal will need to be handled manually."
  echo "We apologize for any inconvenience."

fi

echo ""
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo ""

echo "Proceeding with reset of your local ICPipeline project directory ..."
echo
echo "Archiving your installer logs before reset ..."
echo

if [ -f "${resources_dir}/installer-logs/dfx.build.log" ]; then
  dfx_log_archive_name=dfx.build.log_$(date "+%Y.%m.%d::%H:%M")
  echo "Archiving DFX installer log ..."
  echo
  cp "${resources_dir}/installer-logs/dfx.build.log" "${archive_dir}/${dfx_log_archive_name}"
  if [ -f "${archive_dir}/${dfx_log_archive_name}" ]; then
    echo -e "${green}DFX install log is archived in /installer-logs/archive${clear}"
  else
    echo "Reset was unable to archive your DFX installer log.  Please save your DFX log manually if you'd like to preserve it."
  fi
else
  echo
  echo "DFX build log not found for this installation."
fi

echo

if [ -f "${resources_dir}/installer-logs/npm.build.log" ]; then
  npm_log_archive_name=npm.build.log_$(date "+%Y.%m.%d::%H:%M")
  echo "Archiving NPM installer log ..."
  echo
  cp "${resources_dir}/installer-logs/npm.build.log" "${archive_dir}/${npm_log_archive_name}"
  if [ -f "${archive_dir}/${npm_log_archive_name}" ]; then
    echo -e "${green}NPM install log is archived in /installer-logs/archive${clear}"
  else
    echo "Reset was unable to archive your NPM installer log.  Please save your NPM log manually if you'd like to preserve it."
  fi
else
  echo
  echo "NPM build log not found for this installation."
fi

echo

if [ -f "${resources_dir}/installer-logs/aws.build.log" ]; then
  aws_log_archive_name=aws.build.log_$(date "+%Y.%m.%d::%H:%M")
  echo "Archiving AWS installer log ..."
  echo
  cp "${resources_dir}/installer-logs/aws.build.log" "${archive_dir}/${aws_log_archive_name}"
  if [ -f "${archive_dir}/${aws_log_archive_name}" ]; then
    echo -e "${green}AWS install log is archived in /installer-logs/archive${clear}"
  else
    echo "Reset was unable to archive your AWS installer log.  Please save your AWS log manually if you'd like to preserve it."
  fi
else
  echo
  echo "AWS build log not found for this installation."
fi

echo

# (manually maintained) array of local fs items to remove on reset
installer_artifacts=("${resources_dir}"/cloudconf/aws/icpw-task-definition.json \
                     "${resources_dir}"/cloudconf/aws/aws_deletes_reverse_order.tmp \
                     "${project_home_dir}"/worker.config.env \
                     "${project_home_dir}"/ecs_ami_for_profile_region.json \
                     "${icpm_dir}"/canister_ids.json \
                     "${icpw_dir}"/worker.config.env \
                     "${icpm_dir}"/.dfx \
                     "${icpm_dir}"/node_modules \
                     "${resources_dir}"/installer-logs/aws.build.log \
                     "${resources_dir}"/installer-logs/npm.build.log \
                     "${resources_dir}"/installer-logs/dfx.build.log \
                     "${resources_dir}"/installer-logs/vpn.build.log \
                     "${resources_dir}"/util/easy-rsa \
                     "${resources_dir}"/vpn-client-config \
                     "${icpw_dir}"/id_ed25519_icpipeline.pub \
                     "${resources_dir}"/ecs-container-instance-ssh-key
                     "${resources_dir}"/worker-ssh-key/id_ed25519_icpipeline)

for artifact in "${installer_artifacts[@]}"
do
  sleep .5
  found=false
  if [ -d "${artifact}" ]
  then
    rm -rf "${artifact}"
    found=true
  elif [ -f "$artifact" ]
  then
    rm -f "${artifact}"
    found=true
  else
    echo -e "${yellow}Reset did not detect ${artifact} on local filesystem.${clear}"
  fi
  if [ -d "${artifact}" ] || [ -f "${artifact}" ]
  then
    echo -e "${red}Reset encountered a problem removing ${artifact}, intervention is required.${clear}"
  else
    if [[ ${found} == true ]]
    then
      echo -e "${green}Reset successfully removed ${artifact}${clear}"
    fi
  fi
done

# invite user to execute canister reset script generated above
if [[ -f "${f}" ]]
then

  echo
  echo "Canister reset is ready to go, and we can run it now."
  echo
  echo -e "${yellow}CANISTER RESET WILL PERMANENTLY REMOVE BOTH ICPM CANISTERS FROM THE INTERNET COMPUTER${clear}."
  echo
  echo "It is a good idea, before destroying ICPM, to first export your ICPM data.  This data is essentially the history"
  echo "of this particular ICPipeline implementation: your Projects, Environments, Deployments and so forth.  Note that we're referring"
  echo "only to data that is internal to ICPM itself.  It's not part of your actual projects, which are not affected by this at all."
  echo
  echo "To save your data, just follow the steps (in ICPM --> Settings) to export and save your data locally.  You can even leave this right here,"
  echo "and just press <ENTER> to continue when you're done with that."
  echo
  echo -e "If you do prefer to skip canister reset now, to run separately at a later time, (refer to the ${cyan}ICPM${clear} module README)."
  echo
  echo -e "Reset will report your new cycles balance, including the cycles redeposited in your wallet by the ${magenta}Internet Computer${clear}."
  echo

  isgood=0
  while [[ $isgood == 0 ]]; do

    echo
    read -p "Execute canister reset now? (press <ENTER> to RESET.  Or type and enter \"SKIP\" to skip canister reset at this time): " run_canister_reset
    run_canister_reset=${run_canister_reset:-'YES'} && run_canister_reset=$(echo "${run_canister_reset}" | tr 'A-Z' 'a-z')
    while [[ ! ${run_canister_reset} == "skip" && ! ${run_canister_reset} == "yes" ]]; do invalid_response; done
    if [[ ${run_canister_reset} == "skip" ||  ${run_canister_reset} == "yes" ]]; then isgood=kramden; fi

  done
  if [[ "yes" == "${run_canister_reset}" ]]
  then
    
    echo
    echo -e "Thank you.  Reset is stopping and removing your ${cyan}ICPM${clear} canisters from the ${magenta}Internet Computer${clear}..."
    echo
    (cd ${icpm_dir} && ./reset_installation_ic.sh)
    echo "Done with canister removal, refer to output for details."

  else
    
    echo "OK, we'll leave canister reset for you to execute when ready."
  
  fi

fi

# First verify that we have an AWS resetter to speak of (it was generated by the installer at runtime)
if [[ -f "${aws_resetter}" ]]
then

  echo
  echo -e "The AWS resetter was compiled by the ${cyan}ICPipeline${clear} installer at runtime.  AWS reset"
  echo "removes *every* AWS resource created by its originating installer run.  Your AWS account will be \"clean\""
  echo "from that installation and you'll be set to re-install."
  echo
  echo "As with canister reset, we can do that now from here.  Or you can run it separately."
  echo -e "${yellow}If you do, be sure to run it under the same AWS profile as the installer run.${clear}"
  echo

  isgood=0
  while [[ $isgood == 0 ]]; do

    echo
    read -p "Execute AWS reset now? (press <ENTER> to RESET.  Or type and enter \"SKIP\" to skip AWS reset at this time): " run_aws_reset
    run_aws_reset=${run_aws_reset:-'YES'} && run_aws_reset=$(echo "${run_aws_reset}" | tr 'A-Z' 'a-z')
    while [[ ! ${run_aws_reset} == "skip" && ! ${run_aws_reset} == "yes" ]]; do invalid_response; done
    if [[ ${run_aws_reset} == "skip" ||  ${run_aws_reset} == "yes" ]]; then isgood=kramden; fi

  done # end while isgood = 0

  # If user has opted to run AWS reset
  if [[ "yes" == "${run_aws_reset}" ]]
  then

    echo -e "${cyan}******************************************************************************${clear}"
    echo
    echo -e "AWS won't let us remove your ${cyan}ICPipeline${clear} Fargate or ECS cluster if tasks (i.e. Worker containers) are running in it."
    echo "In the case of ECS, we'll also need to deregister and terminate remaining cluster instances."
    echo "So reset will check for leftover running containers in the cluster, and ask you before stopping them individually."
    echo "Think of it as an excess of caution that we'll ask you to confirm each one.  Alternatively, you can stop your containers"
    echo "from the AWS console or CLI before running reset."
    echo
    echo -e "${yellow}On the off-chance that you may be running other (i.e. non-Worker) containers in your ICPipeline Fargate cluster,"
    echo -e "please be aware that reset will stop ALL containers on that cluster${clear}."
    echo
    echo "Note that \"YES\" is the default here.  <ENTER> will be your affirmative answer, i.e. to stop each Worker task."
    echo
    echo "As mentioned, leftover tasks will prevent AWS reset from running.  This check is just in case you have an"
    echo "unusual edge case, and we are risk-averse about deleting your stuff incorrectly."
    echo
    echo -e "${cyan}******************************************************************************${clear}"

    # *****************************************************************************************************************************************
    # Commence evaluation for AWS reset readiness.  Basically that means screening the container cluster for
    # resources that may still be running on it:
    #  --> For Fargate we're just concerned with running containers.
    #  --> For ECS/EC2 we deal with both containers AND container *instances*.
    # If we detect running resources, containers and/or instances, we'll try to provide low-friction UX, but without it being *too* frictionless.
    # We are deleting resources from folks' accounts, and those resources have stuff on them.
    # On paper these are all dedicated ICPipeline resources.  But a user/team *could* have the family jewels stored on an "ICPipeline" container
    # or instance, and the resetter has no way to know about it.  Indeed, we don't ever want to nose around inside our users' resources, at all.
    # So, that's the thing we want to be careful with, and ensuring that the user is on the same page is the best available way to do it.
    # Goal is to step carefully while still providing a reasonably painless path through a cleanup sequence that can otherwise be pretty obtuse,
    # especially for folks not way deep in AWS.
    # ******************************************************************************************************************************************

    # First query the API for a count of running tasks (Dockers) on the cluster.  This applies in all cases (both FARGATE and EC2-backed containers)
    # The query takes the cluster name, and the task count is (interestingly) an actual static field in the json ...
    # So we don't need do any actual counting, lucky day.
    # Resetter has the cluster name via the .env breadcrumb file dropped by the installer when it created the cluster.
    # (Cluster name is the same whether Fargate or EC2.)
    running_tasks_count=$(aws ecs describe-clusters --clusters "${INSTALLER_ECS_CLUSTER_NAME}" | jq -rc '.clusters[].runningTasksCount')
    
    # If there are tasks left running on the cluster at reset time, they must be dealt with before the cluster can be removed.
    if [[ 0 -lt "${running_tasks_count}" ]]
    then

      echo
      echo -e "${yellow}We have ${running_tasks_count} containers still running on cluster ${INSTALLER_ECS_CLUSTER_NAME}.${clear}"
      echo
      echo "We'll need to stop these ${running_tasks_count} containers before AWS reset can proceed."
      echo
      echo
      echo "Reset will cycle through each container, pausing at each one for your confirmation that you wish"
      echo "to stop it.  If in doubt about stopping any particular container, compare its (displayed) resource ARN with"
      echo "your AWS console for a sanity check."
      echo
      echo "If you're resetting ICPipeline, this is probably a no-brainer, since you really can't complete the AWS component of Reset"
      echo "with containers running on your cluster.  But it's fine if there's a resource you don't want to delete at the moment."
      echo "Just skip the AWS portion of Reset for now, and come back and run it when you're ready."
      echo
      echo "Press <ENTER> to proceed when you're ready.  Even if you plan to leave containers running,"
      echo "go ahead and proceed, and you'll still be able to do so."
      echo
      echo -e "${cyan}******************************************************************************${clear}"
      echo

      pauseforuser

      echo "Gathering info on ${running_tasks_count} running containers ..."

      # Fetch a list of task ARNS of all running Dockers on the ICPipeline cluster.
      worker_task_arns=$(aws ecs list-tasks --cluster "${INSTALLER_ECS_CLUSTER_NAME}")
    
      echo
    
      # Loop the running containers list, requiring explicit "stop" from the user before killing each one.
      for worker_arn in $(echo "${worker_task_arns}" | jq -rc '.taskArns[]'); do
      
        isgood=0
        while [[ $isgood == 0 ]]; do
        
          echo
          echo "This container's resource number (ARN) is ${worker_arn}"
          read -p "Stop this container now? (type and enter \"STOP\".  Or press <ENTER> to skip and leave it running): " stop_worker_task
          stop_worker_task=${stop_worker_task:-'NO'} && stop_worker_task=$(echo "${stop_worker_task}" | tr 'A-Z' 'a-z')
          while [[ ! ${stop_worker_task} == "no" && ! ${stop_worker_task} == "stop" ]]; do invalid_response; done
          if [[ ${stop_worker_task} == "no" ||  ${stop_worker_task} == "stop" ]]; then isgood=kramden; fi
        
        done # End while isgood = 0
        
        if [[ "stop" == "${stop_worker_task}" ]]; then
      
          # Redirecting output to /dev/null because verbosity (though actual pagination should be suppressed)
          aws ecs stop-task --cluster "${INSTALLER_ECS_CLUSTER_NAME}" --task "${worker_arn}" > /dev/null 2>&1
      
        fi # End if user chose to stop a single task

      done # end loop on worker_task_arns array

      # Now re-query to verify no remaining containers on the cluster.  Recycle same vars, is fine.
      running_tasks_count=$(aws ecs describe-clusters --clusters "${INSTALLER_ECS_CLUSTER_NAME}" | jq -rc '.clusters[].runningTasksCount')

      if [[ "${running_tasks_count}" -gt 0 ]]
      then
      
        echo -e "It seems the previous exercise has not left us with a containerless ${cyan}ICPipeline${clear} cluster."
        echo "Please stop your containers from the AWS console or CLI, after which you can re-run reset."
        echo "Hopefully this is because you opted to leave container(s) running.  If not, we apologize for any inconvenience."
        echo
        echo "Reset will exit for now."
        exit 1
    
      else
      
        echo
        echo -e "${green}All remaining containers successfully stopped, AWS reset can proceed.${clear}"
        echo

        sleep 3
      
      fi # End if followup check for running containers

    # If the cluster type is ECS/EC2, we can have running container instances whether containers were running or not.
    # So we tie off the IF-containers logic and address container instance logic in all cases (FARGATE cluster type is excepted below).
    fi # End if running containers were detected.

    # Container instance logic only matters for cluster type EC2, that's irrelevant if Fargate, so ...
    # Screen for cluster type.
    if [[ "ec2" == "${INSTALLER_ECS_CLUSTER_TYPE}" ]]; then

      echo -e "With this installation, you deployed your ${cyan}ICPipeline Worker${clear} containers on ECS/EC2 container instances."
      echo "So we'll also need to check for remaining container instances to prepare for end-to-end AWS reset."
      echo

      # First fetch the list of *container instance* ARNS associated with our ECS cluster (entirely distinct from their EC2 instance ids ... we'll get to those)
      ecs_container_instance_arns=$(aws ecs list-container-instances --cluster "${INSTALLER_ECS_CLUSTER_NAME}")

      # Convert the list to array ... the better to count with.
      container_instance_arns_array=( $(echo "${ecs_container_instance_arns}" | jq -rc '.containerInstanceArns[]') )

      # If running container instances are detected ... We'll message user to proceed with caution, resetter has limited visibility, etc.
      if [[ 0 -lt ${#container_instance_arns_array[@]} ]]; then

        echo
        echo -e "${cyan}******************************************************************************${clear}"
        echo
        echo -e "${yellow}Your ICPipeline ECS cluster has ${#container_instance_arns_array[@]} container instances still running.${clear}"
        echo
        echo "These are not containers (Workers or otherwise).  We've already taken care of those."
        echo "Rather, these are the underlying EC2 instances on which your Worker containers are (or were) hosted."
        echo
        echo "Reset can remove all container instances associated with your ICPipeline cluster."
        echo
        echo "We'll loop through their instance IDs, pausing on each to ask your permission before we terminate"
        echo "each EC2 instance, one at a time.  In the vast majority of cases, this is a no-brainer.  But please take note"
        echo "of the following, just in case:"
        echo
        echo -e "${yellow}IMPORTANT: Reset takes a complete inventory, of ALL the instances associated"
        echo -e "with this cluster.  Reset has no direct visibility to the *actual* contents of the instances.${clear}"
        echo
        echo -e "Only you can be sure that your ${cyan}ICPipeline${clear} container instances contain ONLY ${cyan}ICPipeline Worker${clear} containers"
        echo "(or whatever else, as long as you're OK with deleting it, is the point).  So it's on you to be certain that"
        echo -e "you wish to ${yellow}PERMANENTLY REMOVE your resources from your AWS account.${clear}"
        echo
        echo "Reset will display the instance ID of each resource before proceeding with your permission"
        echo "to terminate it.  If at all unsure, compare the instance ID with your AWS console, or even SSH into the instance,"
        echo "for a final check to be certain before you terminate the resource."
        echo
        echo "We don't like to sound legalistic about it.  But you're terminating instances in your AWS account, and we do need to be careful."
        echo
        echo "For each running instance, when you enter \"TERMINATE\", Reset will first deregister the container instance,"
        echo "effectively disconnecting it from the cluster.  For that one brief moment it's just, as it seems, a regular plain old instance ..."
        echo
        echo "Then Reset, as your proxy, executes your \"TERMINATE\" command."
        echo
        echo "By pressing <ENTER> to proceed, you'll acknowledge that you've read this message, thanks."
        echo
        echo -e "${cyan}******************************************************************************${clear}"
        echo

        pauseforuser

        # Loop the array of container instance ARNS
        for container_instance_arn in $(echo "${ecs_container_instance_arns}" | jq -rc '.containerInstanceArns[]'); do

          # Now iterate through the individual container instances. describe-container-instances returns a json blob, from which we're only interested in the EC2 instance ID.
          ec2_instance=$(aws ecs describe-container-instances --cluster "${INSTALLER_ECS_CLUSTER_NAME}" --container-instances "${container_instance_arn}")

          # Parse instance id from the json.
          ec2_instance_id=$(echo "${ec2_instance}" | jq -rc '.containerInstances[0].ec2InstanceId')

          # Now we have an actual instance id, and we solicit user's direction on what to do with it.
          isgood=0
          while [[ $isgood == 0 ]]; do
  
            echo
            echo "This EC2 container instance is instanceID ${ec2_instance_id}".
            read -p "Terminate this instance now? (type and enter \"TERMINATE\".  Or press <ENTER> to skip and leave this EC2 instance running): " terminate_ec2_instance
            terminate_ec2_instance=${terminate_ec2_instance:-'NO'} && terminate_ec2_instance=$(echo "${terminate_ec2_instance}" | tr 'A-Z' 'a-z')
            while [[ ! ${terminate_ec2_instance} == "no" && ! ${terminate_ec2_instance} == "terminate" ]]; do invalid_response; done
            if [[ ${terminate_ec2_instance} == "no" ||  ${terminate_ec2_instance} == "terminate" ]]; then isgood=kramden; fi
  
          done # End while isgood = 0
  
          # If user has explicitly typed "terminate", first deregister instance from cluster, then terminate the instance.
          if [[ "terminate" == "${terminate_ec2_instance}" ]]; then

            echo
            echo "First we deregister the container instance from the ECS cluster..."
            aws ecs deregister-container-instance --cluster "${INSTALLER_ECS_CLUSTER_NAME}" --container-instance "${container_instance_arn}" --force 2>&1 > /dev/null
            echo
            echo "Then we terminate the EC2 instance ${ec2_instance_id} ..."
            aws ec2 terminate-instances --instance-ids "${ec2_instance_id}" 2>&1 > /dev/null
            echo
  
          fi # End if user has elected to terminate a specific instance

        done # End for loop on ecs_container_instance_arns array

        # At this point the cluster should be free of running instances, one way or the other.
        # We'll confirm by re-running the same checks we started with, message happy time that the coast is clear.

        # Re-fetch the list of container instance ARNS associated with our ECS cluster (it should be empty now, assuming nothing has failed).
        ecs_container_instance_arns=$(aws ecs list-container-instances --cluster "${INSTALLER_ECS_CLUSTER_NAME}")

        # Convert it to array
        container_instance_arns_array=( $(echo "${ecs_container_instance_arns}" | jq -rc '.containerInstanceArns[]') )

        # If running container instances are *not* detected, as should be the case, we're good to go.
        if [[ 1 -gt ${#container_instance_arns_array[@]} ]]; then

          echo -e "${green}Your ICPipeline cluster is now free of running container instances.  AWS reset can now proceed.${clear}"

        else

          echo "Reset still detects running container instances on your ICPipeline cluster.  This will require manual intervention"
          echo "before Reset can seamlessly remove all remaining AWS resources associated with this installation."
          echo "Feel free to touch base if you think we can advise -- we're happy to do so: support@icpipeline.com"

        fi # end if for followup check for stray container instances

      fi # End if running container instances were detected

      # This removes both of the IAM resources that AWS required if this installation used EC2-backed containers.
      echo
      echo -e "${cyan}******************************************************************************${clear}"
      echo
      echo "Your ICPipeline ECS cluster is of the EC2/container-instances type, which required the installer to add an IAM role"
      echo "and its related instance profile to your AWS account.  They're harmless enough, but we'll"
      echo "go ahead and remove them for now.  They'll re-create automatically if needed again in future."
      echo
      echo -e "${cyan}******************************************************************************${clear}"
      sleep 4

      echo
      echo "Detaching role ICPLContainerInstanceRole from instance profile ICPLContainerInstancePolicy ..."
      aws iam remove-role-from-instance-profile --instance-profile-name ICPLContainerInstanceProfile --role-name ICPLContainerInstanceRole
      echo "Detaching role ICPLContainerInstanceRole from the AWS-boilerplate service role policy ..."
      aws iam detach-role-policy --role-name ICPLContainerInstanceRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role
      echo "Deleting instance profile ICPLContainerInstanceProfile ..."
      aws iam delete-instance-profile --instance-profile-name ICPLContainerInstanceProfile
      echo "Deleting IAM role ICPLContainerInstanceRole ..."
      aws iam delete-role --role-name ICPLContainerInstanceRole    
      echo
      echo -e "${cyan}******************************************************************************${clear}"
      echo
      echo "This installation includes container instances, so AWS needs an extra breather between reset commands"
      echo "to manage its internal dependency chain.  Inserting that pause here, before proceeding with the"
      echo "remaining AWS delete sequence."
      echo
      echo "Pausing 90 seconds for AWS dependency management ..."
      echo
      sleep 90
    
    fi # End if cluster type is EC2
  
    # At this point our cluster, irrespective of type, should be an empty shell that can be dropped by AWS reset along with everything else.
    source "${aws_resetter}"

  fi # End if user opted to run AWS reset

  # Preserve AWS resetter script against potential overwrite by subsequent installer runs
  aws_resetter_archive_name=reset_installation_aws_$(date "+%Y.%m.%d::%H:%M")
  echo
  echo "Archiving your AWS reset manifest so it won't be overwritten on a subsequent install ..."
  echo
  cp "${aws_resetter}" "${archive_dir}/${aws_resetter_archive_name}"
 
  if [ -f "${archive_dir}/${aws_resetter_archive_name}" ]; then
 
    echo -e "${green}AWS reset manifest successfully copied to /resources/archive${clear}"
 
  else
 
    echo "Reset was unable to archive your AWS reset manifest.  Please save your AWS reset manifest manually if you'd like to preserve it."
 
  fi

fi # End if AWS resetter asset exists

exit

# Preserve canister resetter script, same reason
if [ -f "${icpm_dir}/reset_installation_ic.sh" ]; then
  
  canister_resetter_archive_name=reset_installation_ic_$(date "+%Y.%m.%d::%H:%M")
  echo
  echo "Archiving your canister reset manifest so it won't be overwritten on a subsequent install ..."
  echo

  cp "${icpm_dir}/reset_installation_ic.sh" "${archive_dir}/${canister_resetter_archive_name}"
  if [ -f "${archive_dir}/${canister_resetter_archive_name}" ]; then
  
    echo -e "${green}Canister reset manifest successfully copied to /resources/archive${clear}"
    rm "${icpm_dir}"/reset_installation_ic.sh
  
  else
  
    echo "Reset was unable to archive your canister reset manifest.  Please save your canister reset manifest manually if you'd like to preserve it."
  
  fi

fi

echo
echo -e "Reset is complete.  We sure hope you're preparing to reinstall ${cyan}ICPipeline${clear}."
echo "The framework includes these tools so that we can break things fearlessly."
echo

echo -e "${cyan}******************************************************************************${clear}"

echo
echo "One final housekeeping note: Your AWS and canister resetter scripts and installer logs are archived by reset."

echo "They are just there as needed, and because they're logs.  They're .gitignore'd, out of the way of"
echo "future installer runs, no need to do anything with them."
echo
echo -e "The scripts are good to retain as historical inventory of your ${cyan}ICPipeline${clear} resources"
echo -e "on the ${magenta}Internet Computer${clear} and in AWS.  Also, you can always take the hands-on approach,"
echo "by copying individual commands from the scripts into a terminal.  That has been known to come in handy, just sayin'."

echo

if [[ "no" == "${run_aws_reset}" ]]
then

  echo "You can run AWS reset whenever you're ready, but note that you may incur AWS costs in the meantime."
  echo "The only real concern would be if idle containers are left running on the Fargate cluster."
  echo "They really get you for those -- like, a couple of bucks a day *per container*."

fi

if [[ "no" == "${run_canister_reset}" ]]
then

    echo "Canister reset is ready whenever you are.  But, if you're done with the canisters, you might as well do it soon."
    echo "Dormant canisters still consume your cycles.  It's really very slow, but still ..."

fi

echo
echo -e "Contact ${cyan}ICPipeline${clear} if you need us, and we'll try to assist."
echo
