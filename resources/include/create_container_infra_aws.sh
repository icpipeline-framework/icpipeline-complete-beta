#!/bin/bash

# This module builds AWS infrastructure (either ECS or Fargate), and runs as many
# ICPipeline Worker containers as you tell it.  It runs either as an include of the framework installer,
# or freestanding.  If freestanding you need a VPC/subnet, and you'll also need to fill in some variable values below.
# If run as installer include, all that stuff should inherit from the parent module.

# This function sorts through any input args received (args will vary by use case),
# and sets internal vars accordingly.  It also makes it so received args can be in any order,
# and typed in any cAsE.  None of that should matter as long as the information is there...
# and anyway this is all in the code and of no concern to users in normal operations, just sharing.
process_args "${@}"

# Individual container sizing (not to be confused with container *instance* sizing).
# This per-container sizing applies in all cases, whether using ECS/EC2 or Fargate.
per_worker_cpu_units="1024"
per_worker_ram_bytes="2048"

# BASIC CONTAINER INSTANCE PARAMETERS (N/A if using Fargate for container infra):
# NOTE that we use the AWS-recommended AMI for these instances.
# The AMI ID is region-specific (i.e. the same image has a different ID per-region).
# Here again, the installer references the user's profile, dynamically fetching the AMI ID
# associated with the default region specified in the user's AWS profile.

# Container *instance* type/size:
# NOTE: m5.large is the "recommended instance type" for the AMI we use (ECS-Optimized Amazon Linux 2).
# Obviously sizing is a generalization.  You would size to suit using common sense, with the m5
# base indicating that they think a "general use" "M" type image is a good fit
# for container instances.
container_instance_size="m5.large"

# The number of container instances to launch (this applies only to ECS/EC2, is N/A with Fargate)
# NOTE: this is distinct from container count, which applies in all cases.
container_instance_count="2"

# *****************************************************************************************************
# Define conditional vars (based on whether "include" is passed as input; if not they're defined here).
# Placing these first because they trickle-down in a few cases into the always-local vars that follow.
# *****************************************************************************************************
if [[ ! true == ${include} ]]; then

  # ************************************************************
  # local filesystem housekeeping, paths etc.
  # ************************************************************
  # NOTE: if you run this standalone, do it right here in /resources/include, or all bets are off.
  project_home_dir=../..
  resources_dir=${project_home_dir}/resources
  icpw_dir=${project_home_dir}/worker-docker-dev

  # Include formatting in case standalone
  source ${resources_dir}/include/formatting.sh
  
  # ...and this does no harm to re-run, in the same case.
  process_args "${@}"

  # The Worker Docker build needs worker.config.env, one way or the other.
  # Among other things it contains the canister id(s) of the ICPM d'app the Worker is to register with.
  # The file initially compiles as just plain .env, and gets copied in.
  # The local .env, once copied into the docker as worker.config.env, has no direct function.
  # The local copy is kept for reference, troubleshooting, etc.
  # NOTE: if this NOT run in conjunction with the ICPM canister module, the canister ids will
  # need to come from somewhere.  Will include placeholders for the static variety.
  # Supply them with values as needed.
  dotenv_file="${project_home_dir}/worker.config.env"

  # check for any .env file remnants, possible leftovers from a previous partial install.
  f="${dotenv_file}"
  if [ -f "${f}" ]
  then
    rm -f "${f}"
    touch "${f}"
  else
    touch "${f}"
  fi
  unset f

  # A placeholder for statically-placed canister ids, in the event this is NOT run in conjunction
  # with an ICPM build.  In order to really be Workers, they need to know who their Mama is.
  data_canister_id=""
  assets_canister_id=""

  echo -n "ICPM_CANISTER_ID=$data_canister_id" | xargs >> "${dotenv_file}"
  echo -n "ICPM_ASSETS_CANISTER_ID=$assets_canister_id" | xargs >> "${dotenv_file}"

  # *************************************************************************
  # Read in AWS profile settings if they're not inherited from the installer.
  # *************************************************************************

  # fetch aws account id from user's aws profile, write it to .env file
  aws_account_id=$(aws sts get-caller-identity | jq '.Account' | tr -d '"')

  echo "AWS_ACCOUNT_ID=${aws_account_id}" | xargs >> "${dotenv_file}"
  # echo "AWS_ACCOUNT_ID=${aws_account_id}"
  
  # likewise aws region
  aws_region=$(aws configure get region)
  
  echo "AWS_REGION=${aws_region}" | xargs >> "${dotenv_file}"
  # echo "AWS_REGION=${aws_region}"
  
  # ...and availability zone.
  # NOTE: this returns the "first" availability zone (meaning @position[0] in the returned array for the region)
  # in the user profile's designated region.
  aws_availability_zone=$(aws ec2 describe-availability-zones --region ${aws_region} | jq '.AvailabilityZones[0].ZoneName' | tr -d '"')
  echo "AWS_AVAILABILITY_ZONE=${aws_availability_zone}" | xargs >> "${dotenv_file}"
  
  # AWS networking VPC/Subnet(s)
  # If these resources aren't inherited from the installer, this script will have to be told where to go.
  # So you'd fill in these values in a given ad hoc situation, not really what this is built for ...
  vpc_id=""
  public_subnet_id=""
  private_subnet_id=""

  # Define our aws_build_log file if it doesn't come from the installer.
  aws_build_log="${resources_dir}"/installer-logs/aws.build.log
  
  # Append a psuedorandom numeric suffix to ECS/Docker resource names.
  # This essentially bundles the resources for a build, while avoiding AWS namespace collisions.
  # This needs a bit more "entropy" than RANDOM's native limit of 32767.
  sol=99
  re=$(($RANDOM%sol))
  mi=$(($RANDOM%sol))
  fa=$(($RANDOM%sol))
  session_random=$re$mi$fa

  # Suppresses pagination of verbose AWS CLI outputs.
  export AWS_PAGER=""

  # Ports on which to allow remote access to our Worker network.
  # NOTE: the same ports will be opened on both individual Worker containers,
  # and on (ECS/EC2 only) container instances.  The security groups and SSH keys will be distinct and separate,
  # but the default open ports will be the same.
  # It will be trivial to break this out further, but we're shooting for KISS and will heed community feedback.
  ingress_ports_unique=(22 8080)

  # Defines source address or range for Worker (and container instance) remote access.
  # On full framework installs, the UI accomodates a user-input source range.  Here it's wildcard or tweak the var.
  ingress_cidr_block="0.0.0.0/0"

  # Password for the icpipeline admin system user on Worker Ubuntu OS.
  # NOTE this is failsafe/backstop that will not be in play except in cases of extremest user apathy.
  # Users are encouraged below to disable password auth, or to input a respectable password at the very least.
  # This is mainly to declare the var, with this being marginally better than "".
  icpw_user_pw="ICPIPELINE"

  # This is referenced when building the task definition, essentially needs to match
  # public vs private subnet depending on the chosen Network Mode for the install.
  # #HARDCODE
  mode_subnet_id=${public_subnet_id}
  
  # The number of containers to run on the cluster at install.
  # NOTE: not to be confused with container instance count (if running ECS/EC2).
  number_of_workers="2"

  # NOTE: set either "ENABLED" or "DISABLED" (case-sensitive)
  # NOTE: this setting applies to FARGATE only.  With ECS container instances,
  # Worker containers will have private IPs only (though they will still have individual ENI's).
  # This is an AWS limitation, we'll be very happy if/when it goes away.
  # Anyway this matters only IF this is a standalone run AND you're running Fargate containers.
  # It inherits from the installer, and is meaningless for ECS/EC2-backed Dockers.
  enable_public_ips="ENABLED"

  # This is relating to the installer "Network Mode", i.e. Private or Public.
  # Specifically, in Private Network Mode our Worker Containers deploy into the private subnet
  # of our two-subnet VPC.  In Public Network Mode they live in the public and sole subnet of the VPC.
  # So if this runs as include to the installer we'll set mode_subnet_id according to that.
  # However, if standalone we'll go with common sense.

  # Theoretically this one *could* need a tweak in certain standalone cases.
  # (i.e. it is possible to use Fargate with private networks)
  [[ "FARGATE" == ${ecs_launch_type} ]] && mode_subnet_id=${public_subnet_id}
  # Whereas this is theoretically always correct, because AWS doesn't allow EC2-backed containers to be public.
  [[ "EC2" == ${ecs_launch_type} ]] && mode_subnet_id=${private_subnet_id}
  # Like I said, you might need a tweak here if standalone.  That's an edge case in itself, where you'd know what you're doing ...

  # ...and, (re)define our AWS resetter tools here, on the off chance that this is standalone. 
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

fi # end if include or freestanding

# Now the same mode_subnet_id deal as applies in proper framework install settings.
# Here the logic is clear-cut and should be bulletproof.
[[ true == ${public_network_mode} ]] && mode_subnet_id=${public_subnet_id}
[[ true == ${private_network_mode} ]] && mode_subnet_id=${private_subnet_id}

# ***********************************************************************************
# Now define vars that always live in this module (whether as include or standalone).
# These are declared here and here only.
# ***********************************************************************************

# name the ssh key for container instances (applies to ECS/EC2 only)
# NOTE: this value will be prepended with "id_rsa_" for the actual keyfile name (ed25519 not available here, per AWS).
container_instance_keypair_name="icpipeline_container_instance"

# Primary container resource names get a matching random number suffix that is specific to this build.
# This is a useful sanity check in cluttered AWS accounts.

# Docker image name (not actually referenced in our Docker Buildkit syntax at the moment.  But that could change, so we'll keep it in)
docker_image_name="icpipeline-image-${session_random}"

# The ECR repository name (where the container image lives ... I think the image inherits the repo name, re previous comment)
ecr_repository_name="icpipeline-ecr-repo-${session_random}"

# The cluster name -- cluster name (and the basic cluster itself) is the same whether ECS/EC2 or Fargate.
ecs_cluster_name="icpipeline-cluster-${session_random}"

# While we're here, write the cluster name to the resetter breadcrumbs file
echo "INSTALLER_ECS_CLUSTER_NAME=${ecs_cluster_name}" >> ${resources_dir}/util/installation_vars.env

# The ECS task definition name
task_definition_name="icpipeline-task-def-${session_random}"

# name tag for container instance security group
container_instance_sg_name_tag="ICPipeline Container Instance Security Group"

# Names for the interconnected IAM role and instance profile required.
# (this applies only to ECS/EC2. Fargate doesn't involve IAM other than the permissions in the user's profile)
# NOTE: these (perfectly adequate, descriptive) resource names are coded into the resetter.  So if (for some reason)
# you wanted to change them, you'd also want to tweak reset_installation_main.sh to match, in order for ICPipeline reset
# to deal gracefully with these particular resources.
container_instance_iam_role_name="ICPLContainerInstanceRole"
container_instance_profile_name="ICPLContainerInstanceProfile"

# Here we run the command and output it to ./ecs_ami_for_profile_region.json
# That file will contain your AMI ID if you need to change it based on your profile region.  Working on the better mousetrap.
echo $(aws ssm get-parameters --names /aws/service/ecs/optimized-ami/amazon-linux-2/recommended --region ${aws_region}) | jq . | less -R > ecs_ami_for_profile_region.json

# A bit caveman with sed here to be sure, but AWS formats this particular JSON weirdly, and there's so much to do ...
sed -i '' 's/\\//g' ecs_ami_for_profile_region.json
sed -i '' 's/"{/{/g' ecs_ami_for_profile_region.json
sed -i '' 's/}"/}/g' ecs_ami_for_profile_region.json
container_instance_ami_id=$(cat ecs_ami_for_profile_region.json | jq -r '.Parameters[0].Value.image_id')

# ********************************
# commence actually building stuff
# ********************************

# First create the cluster -- same basic skeleton whether EC2 or Fargate.
echo "Creating cluster name ${ecs_cluster_name} ..."
echo "Output from create ECS/Fargate cluster:" >> "${aws_build_log}"
aws ecs create-cluster --cluster-name "${ecs_cluster_name}" --output yaml-stream >> ${aws_build_log}


# Add delete cluster entry to AWS resetter script
echo -e "\n" >> "${aws_resetter_script_reverse}"
echo "aws ecs delete-cluster --cluster ${ecs_cluster_name} --output yaml-stream 2>&1 > /dev/null" >> "${aws_resetter_script_reverse}"
echo "echo \"Deleting ECS Fargate cluster ${ecs_cluster_name} ...\"" >> "${aws_resetter_script_reverse}"

# This is all the stuff required only for ECS/EC2 launch type (i.e. running container instances as opposed to Fargate)
if [[ "EC2" == ${ecs_launch_type} ]]; then

  # Off the top, IF our cluster has container instances, there's another AWS lag after instance deletes, before it
  # will allow the VPC to be dropped.  So we inject this pause into the resetter IF it's EC2 cluster type.
  # Should have the desired effect almost anywhere in the AWS resetter ... what counts is elongating the interval between
  # instance deletes and VPC delete (which is the very last thing to go).
  # # Add required pause entry to the resetter.
  # echo -e "\n" >> "${aws_resetter_script_reverse}"
  # echo "sleep 90" >> "${aws_resetter_script_reverse}"
  # echo "echo \"Pause ...inducing a time interval between container instance deletes and VPC delete ... AWS insists.\"" >> "${aws_resetter_script_reverse}"

  # ********************************************************************************
  # generate a keypair for our ecs container instance(s) and extract the private key
  # ********************************************************************************

  # generate the key pair, dumping raw api output to a json scratch file
  aws ec2 create-key-pair --key-name ${container_instance_keypair_name} > container-image-keypair.json

  # extract aws id of the keypair for use as needed
  container_instance_keypair_id=$(cat container-image-keypair.json |  jq '.KeyPairId' |tr -d '"')

  # create a named folder inside /resources to hold the private key
  mkdir ${resources_dir}/ecs-container-instance-ssh-key

  # mash out a functional keyfile from the scratch file (infile | jq | sed | tr > keyfile ... indeed)
  cat container-image-keypair.json | jq '.KeyMaterial' | sed 's/\\n/\n/g' | tr -d '"' > ${resources_dir}/ecs-container-instance-ssh-key/id_rsa_${container_instance_keypair_name}

  # Add delete container instance key pair entry to AWS resetter script
  echo -e "\n" >> "${aws_resetter_script_reverse}"
  echo "aws ec2 delete-key-pair --key-name ${container_instance_keypair_name} --output yaml-stream" >> "${aws_resetter_script_reverse}"
  echo "echo \"Deleting container instance key pair ${container_instance_keypair_name} ...\"" >> "${aws_resetter_script_reverse}"
  
  # *****************************************************************
  # create a security group for container instance(s) (ECS/EC2 only).
  # *****************************************************************

  # NOTE it *might* actually be *better* to use one SG across the board for instances and Workers ... TBD
  # we'll make a dedicated one in the meantime
  create_container_instance_sg_output=$(aws ec2 create-security-group --group-name "$container_instance_sg_name_tag" --description "Private: ${container_instance_sg_name_tag}" --vpc-id "$vpc_id" --output json)

  # extract security group id from aws api response
  container_instance_security_group_id=$(echo -e "$create_container_instance_sg_output" | jq '.GroupId' | tr -d '"')

  # echo "sg id: ${container_instance_security_group_id}"
  # assign name tag to security group
  echo "Tagging container instance(s) security group ${container_instance_security_group_id} as \"${container_instance_sg_name_tag}\" ..."
  aws ec2 create-tags --resources "${container_instance_security_group_id}" --tags Key=Name,Value="${container_instance_sg_name_tag}"

  # Add delete container instance security group to AWS resetter script
  echo -e "\n" >> "${aws_resetter_script_reverse}"
  echo "aws ec2 delete-security-group --group-id ${container_instance_security_group_id} --output yaml-stream" >> "${aws_resetter_script_reverse}"
  echo "echo \"Deleting security group for container instances ${container_instance_security_group_id} ...\"" >> "${aws_resetter_script_reverse}"

  # poke the usual holes in the security group (if running this alone, tweak to suit using array var above)
  for tcp_port in "${ingress_ports_unique[@]}"
  do
    
    echo "Enabling remote access to container instance(s) on port ${tcp_port} ..."
    # echo "Output from enable ingress to Workers on port ${tcp_port}:" >> "${aws_build_log}"
    aws ec2 authorize-security-group-ingress --group-id "${container_instance_security_group_id}" --protocol tcp --port "${tcp_port}" --cidr "${ingress_cidr_block}" --output yaml-stream 2>&1 > /dev/null
  
  done

  # ******************************************************
  # NOTE: running ECS/EC2-backed Dockers requires an IAM role and its associated instance profile.
  # Indeed, the two entities are quasi-synomymous.  (Obviously) these need to be created only once in any given AWS account.
  # So we simply pass (or not) an input arg of "iam" when invoking script.  It can come in any place in the *args* order, case-insensitive.
  # When the occasion fits, just tack on some form of "iam/IAM/IaM", anywhere after the filename when you call it.
  # This is relevant ONLY for creating EC2-backed Dockers in Private Network Mode.  Otherwise the runtime arg is omitted,
  # in which case the IAM commands below are skipped, the role and instance profile (if even needed) already exist, and we're in business.
  # ******************************************************

  if [[ true == ${iam} ]]; then
  
    # first create an iam role, assigning the required boilerplate trust policy (not the actual operational policy)
    aws iam create-role --role-name ${container_instance_iam_role_name} --assume-role-policy-document file://${resources_dir}/cloudconf/aws/ecs_container_instance_trust_policydoc.json 2>&1 > /dev/null

    # then assign the *actual* policy to the role...the one that enables our container instances to do stuff in ECS/ECR/EC2
    # NOTE this references a standard service role policy, extant by default in every AWS account ... will revisit/future-proof
    aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role --role-name ${container_instance_iam_role_name} 2>&1 > /dev/null

    # then create an instance profile ... because it would be too simple if roles could be directly assigned to instances.
    aws iam create-instance-profile --instance-profile-name ${container_instance_profile_name} 2>&1 > /dev/null

    # now assign the IAM role to the instance profile, the thing that finally gets attached to our instance(s) on launch.
    aws iam add-role-to-instance-profile --role-name ${container_instance_iam_role_name} --instance-profile-name ${container_instance_profile_name} 2>&1 > /dev/null

    # wait, now we must retrieve the new instance profile arn, because the name appears to be useless when attaching it to instances.
    instance_profile_arn=$(aws iam get-instance-profile --instance-profile-name ${container_instance_profile_name} | jq '.InstanceProfile.Arn' | tr -d '"')

    # This is just FYI for the curious.
    # To roll back the IAM piece by hand, run the following commands in this order:
    # aws iam remove-role-from-instance-profile --instance-profile-name ICPLContainerInstanceProfile --role-name ICPLContainerInstanceRole
    # aws iam detach-role-policy --role-name ICPLContainerInstanceRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role
    # aws iam delete-instance-profile --instance-profile-name ICPLContainerInstanceProfile
    # aws iam delete-role --role-name ICPLContainerInstanceRole
    # (This is purely FYI.  There's no need for hands-on in normal operation, it's handled automatically by the resetter.)

  fi # end if true == "IAM" (meaning it's ECS/EC2, and first-time only)

  # Generate a user-data script containing our cluster name, to pass to the launch-instance command.
  # ... this is how the EC2's know specifically which cluster to register with (AWS internal stuff).
  echo "#!/bin/bash" > container_image_user_data_script
  echo "echo ECS_CLUSTER=${ecs_cluster_name} >> /etc/ecs/ecs.config" >> container_image_user_data_script

  # Our new instance profile is entirely useless for a brief spell (as we learned the hard way), so we give it a moment.
  echo "Pausing 30 seconds before launching your instance(s).  Allows for AWS latency with the just-created instance profile."
  sleep 30

  # Launch container instances.
  aws ec2 run-instances \
  --image-id "${container_instance_ami_id}" \
  --count "${container_instance_count}" \
  --instance-type "${container_instance_size}" \
  --key-name ${container_instance_keypair_name} \
  --security-group-ids ${container_instance_security_group_id} \
  --subnet-id "${public_subnet_id}" \
  --iam-instance-profile Arn=${instance_profile_arn} \
  --user-data file://container_image_user_data_script \
  --output yaml-stream 2>&1 > /dev/null

  # Clean up a couple of scratch/work files, they're no further use.
  rm container_image_user_data_script && rm container-image-keypair.json

fi # end if build type EC2

# *******************************************************************************************
# Now back on track where it's mostly the same whether our Dockers are EC2-backed or Fargate.
# (not identical, but *mostly* consistent)
# *******************************************************************************************

# Create an authenticated session with ECR, passing the (24-hour TTL) token to Docker.
echo "aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin ${aws_account_id}.dkr.ecr.${aws_region}.amazonaws.com"
aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin ${aws_account_id}.dkr.ecr.${aws_region}.amazonaws.com

# Generate the json for configuring the task definition.  The ecs_launch_type var is the primary distinction.
echo "{\"family\":\"${task_definition_name}\",\"networkMode\":\"awsvpc\",\"containerDefinitions\":[{\"name\":\"icpipeline-worker\",\"image\":\"${aws_account_id}.dkr.ecr.${aws_region}.amazonaws.com/${ecr_repository_name}:latest\",\"essential\": true}],\"requiresCompatibilities\":[\"${ecs_launch_type}\"],\"cpu\":\"${per_worker_cpu_units}\",\"executionRoleArn\":\"arn:aws:iam::${aws_account_id}:role/ecsTaskExecutionRole\",\"memory\":\"${per_worker_ram_bytes}\"}" > ${resources_dir}/cloudconf/aws/icpw-task-definition.json

# ... and pass it to task definition registration
echo "Registering ECS task definition ..."
echo "Output from create ECS task definition:" >> "${aws_build_log}"
aws ecs register-task-definition --cli-input-json file://${resources_dir}/cloudconf/aws/icpw-task-definition.json --output yaml-stream >> "${aws_build_log}"

# Add deregister task definition entry to aws resetter script
echo -e "\n" >> "${aws_resetter_script_reverse}"
echo "aws ecs deregister-task-definition --task-definition ${task_definition_name}:1 --output yaml-stream 2>&1 > /dev/null" >> "${aws_resetter_script_reverse}"
echo "echo \"Deregistering (deleting) task definition revision ${task_definition_name}:1 ...\"" >> "${aws_resetter_script_reverse}"

#  Create Docker image repository in ECR ... no difference at all here.
echo -e "Creating creating repository ${ecr_repository_name} ..."
create_repo_output="$(aws ecr create-repository --repository-name ${ecr_repository_name} --output json 2>&1)"
echo "Output from create ECR repository:" >> "${aws_build_log}"
echo "${create_repo_output}" >> "${aws_build_log}"

# Add delete ECR repo entry to AWS resetter script
echo -e "\n" >> "${aws_resetter_script_reverse}"
echo "aws ecr delete-repository --repository-name ${ecr_repository_name} --force --output yaml-stream 2>&1 > /dev/null" >> "${aws_resetter_script_reverse}"
echo "echo \"Deleting ECR repository ${ecr_repository_name} ...\"" >> "${aws_resetter_script_reverse}"

# Docker Buildkit build and push (of the ICPipeline Worker module Docker image --> to the ECR repo).
docker buildx build \
  --platform linux/amd64 \
  --build-arg ICPW_USER_PW=${icpw_user_pw} \
  --push \
  -o type=registry \
  -t ${aws_account_id}.dkr.ecr.${aws_region}.amazonaws.com/${ecr_repository_name}:latest \
  ${icpw_dir}/.

echo
echo "Your AWS networking and container modules have finished."
echo
echo "For our very last step, the installer module is running your ${number_of_workers} ICPipeline Workers now ..."
echo
sleep 3

# Assemble our Docker run command, where, if it's Fargate, we tag on the syntax for public IP enablement.
# ECS/EC2 type doesn't like it, regardless of what value we put in.  So we disappear it by just passing an empty string.
launch_type_append="" && if [[ "FARGATE" == ${ecs_launch_type} ]]; then launch_type_append=",assignPublicIp=ENABLED"; fi

[[ true == ${private_network_mode} ]] && container_vpc_network_configuration="awsvpcConfiguration={subnets=[${private_subnet_id}],securityGroups=[${worker_security_group_id}]}"
[[ true == ${public_network_mode} ]] && container_vpc_network_configuration="awsvpcConfiguration={subnets=[${public_subnet_id}],securityGroups=[${worker_security_group_id}],assignPublicIp=ENABLED}"

# Finally we run some actual containers huzzah.
# aws ecs run-task --cluster ${ecs_cluster_name} \
# --task-definition ${task_definition_name}:1 \
# --count ${number_of_workers} \
# --launch-type ${ecs_launch_type} \
# --network-configuration "awsvpcConfiguration={subnets=[${mode_subnet_id}],securityGroups=[${container_instance_security_group_id}]${launch_type_append}}" \
# --output yaml-stream  >> "${aws_build_log}"

aws ecs run-task --cluster ${ecs_cluster_name} \
--task-definition ${task_definition_name}:1 \
--count ${number_of_workers} \
--launch-type ${ecs_launch_type} \
--network-configuration ${container_vpc_network_configuration} \
--output yaml-stream  >> "${aws_build_log}"




echo
echo "Container module is complete, returning now to main installer module."
echo
sleep 2