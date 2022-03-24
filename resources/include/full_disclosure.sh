#!/bin/bash

# Inform our users before we start going hog-wild.  Kidding aside, this is a relatively large-footprint operation,
# and we really hope to avoid taking folks by surprise.
echo
echo "IMPORTANT: PLEASE READ"
echo
echo -e "Greetings, and thanks for your interest in ${cyanbold}ICPipeline${clear}.  This is to inform you about the ${cyanbold}ICPipeline${clear} installation"
echo "process and what it entails, so we won't give you any surprises."
echo
echo "--> The installer will first verify some requirements on your system."
echo
echo "--> Then you'll select some important options relating to your installation."
echo "    Options are explained as they come up in the workflow, and the READMEs have longer-form info."
echo
echo "Once requirements verification and information gathering are complete, the installer will:"
echo
echo -e "--> Build some network resources in AWS (a VPC with one or two subnets) to host your IC replica ${cyanbold}ICPipeline Workers${clear}."
echo
echo -e "--> Clone, build and deploy your ${cyanbold}ICPipeline Manager (aka ICPM)${clear} d'app to the ${magentabold}Internet Computer${clear}."
echo
echo -e "--> Return to AWS to deploy Docker infrastructure for your containerized ${cyanbold}ICPipeline Workers${clear}."
echo
echo -e "--> Finally, everything gets tied together, and we run your ${cyanbold}Worker${clear} containers -- however many you decide."
echo
echo "If you select the Private Network Mode option, then a VPN may be a big plus for easy connectivity.  There's a module for that."
echo "Just select \"Add a VPN\", and the installer will create one as part of your finished framework."
echo
echo "This introduction is very condensed indeed.  The installer performs quite a few steps along the way."
echo "Your screen output will keep you informed each step of the way.  There's quite a bit of that, and it is"
echo "worthwhile to follow along.  Everything is in very clear language meant to keep you up to speed.  Your installation"
echo "will look and flow better in a roomy terminal window, and it will be easier to follow along.  Narrower won't break"
echo "anything, but we suggest a baseline of >=130 wide."
echo
echo "Your privacy is paramount to us, as are the general principles of decentralized tech and Web3.  No data is"
echo -e "collected or piped anywhere, or to anyone, during your installation or afterward.  Your ${cyan}ICPipeline${clear} framework"
echo "is all yours: a dedicated end-to-end implementation with no co-tenants, shared components, or \"mothership\" entity."
echo
echo -e "${cyan}******************************************************************************"
echo -e "******************************************************************************${clear}"
echo
echo "If you choose <CONTROL-D> to exit now, no harm done.  But we think you'll miss out on something good,"
echo -e "This is just full disclosure, and we really hope you choose to proceed with your ${cyanbold}ICPipeline${clear} installation."
echo -e "We've worked hard to deliver something of real, practical value to the ${magentabold}Internet Computer community${clear}"
echo
echo "Our success is your success."
echo
echo -e "${yellow}BTW, we'll verify this again farther along, but if Docker Engine is not already running, you really should"
echo -e "start that now, allowing a moment for it to be fully up, before proceeding.${clear}"
echo
echo "For an itemized review of the installation process before proceeding, type and enter \"MORE\" now."
echo
echo "Otherwise just press <ENTER> to skip ahead and proceed.  The installer will walk you right through,"
echo "and the READMEs have additional details when you need them."
echo

isgood=0
while [[ $isgood == 0 ]]; do

  read -p "Read more before proceeding? (type and enter \"MORE\" to see more info, or <ENTER> to skip and proceed): " skip_preview
  skip_preview=${skip_preview:-'NO'} && skip_preview=$(echo "${skip_preview}" | tr 'A-Z' 'a-z')
  while [[ ! ${skip_preview} == "more" && ! ${skip_preview} == "no" ]]; do invalid_response; done
  if [[ ${skip_preview} == "no" ||  ${skip_preview} == "more" ]]; then isgood=1; fi

done

# **************************************************************************************************************
# Content for optional/longer-form install preview goes below, where it may be viewed at the user's option.
# Anything mandatory and/or having disclosure/legal ramifications belongs above, where it will always be viewed.
# **************************************************************************************************************

if [[ ${skip_preview} == "more" ]]; then

  echo
  echo -e "${cyan}******************************************************************************"
  echo -e "******************************************************************************${clear}"
  echo
  echo -e "The options you select during installation will materially affect ${cyan}ICPipeline${clear} implementation."
  echo
  echo "We've made things as clear and readable as possible, and the READMEs contain more detail if/when you need it."
  echo
  echo -e "${green}Note that input validations are case-neutral.  Lowercase works fine if that's more convenient.${clear}"
  echo
  echo -e "This installer creates a complete ${cyanbold}ICPipeline${clear} implementation, end-to-end."
  echo
  echo "Assuming you have the tools onboard, installation time should be the range of 15-25 minutes."
  echo
  echo "As mentioned above, the installer will verify that your machine has the tooling necessary to complete your"
  echo -e "${cyanbold}ICPipeline${clear} installation."
  echo
  echo "Here's the list of (mostly standard) installation requirements:"
  echo
  echo -e "--> ${graylightbold}AWS CLI${clear}"
  echo -e "--> ${graylightbold}AWS/IAM profile${clear} (refer to ${cyanbold}ICPipeline${clear} documentation for permissions specifics)."
  echo -e "--> Your cloned ${cyanbold}ICPipeline${clear} bundle, for basic intactness."
  echo -e "--> ${graylightbold}Node (^16) and NPM (^7)${clear}"
  echo -e "--> ${graylightbold}Dfinity Canister SDK (DFX)${clear}"
  echo -e "--> ${graylightbold}Docker Engine${clear}"
  echo -e "--> ${graylightbold}Git${clear}"
  echo -e "--> ${graylightbold}JQ${clear} (a lightweight JSON parser for bash)."
  echo
  echo
  echo -e "${cyan}******************************************************************************"
  echo -e "******************************************************************************${clear}"
  echo
  echo
  echo "After requirements verification, the installer proceeds to gathering the information necessary to tailor"
  echo -e "${cyanbold}ICPipeline${clear} to your preferences and requirements."
  echo
  echo "These are the specific items for which installer takes your inputs and builds accordingly.  Each option is"
  echo "further explained in context, as it comes up in the installer workflow."
  echo
  echo -e "--> You'll choose either ${graylightbold}Private Network Mode${clear} or ${graylightbold}Public Network Mode${clear} for your"
  echo -e "    ${cyanbold}ICPipeline${clear} framework implementation.  Your selection determines the architecture of the network"
  echo -e "    where your containerized ${cyan}ICPipeline Workers${clear} live.  This is fairly standard stuff, and standard conventions apply."
  echo "    Private networks are generally more secure, but a little less convenient.  Public networks, vice versa."
  echo -e "    We worked hard to deliver the tools to make your private ${cyan}ICPipelines${clear} convenient, and your public ones still secure."
  echo
  echo -e "    These tools extend past the underlying architecture, right into your unencumbered workflows in the ${cyanbold}Pipeline Manager${clear} d'app."
  echo "    Your dashboard, so to speak, has the buttons -- so you can just \"Connect\".  To the extent that port forwarding,"
  echo "    reverse-tunneling, etc. come into play, it's seamless and nearly invisible, very much out of the way for you and your team."
  echo
  echo -e "--> You'll supply a valid GitHub auth token for your GitHub account."
  echo -e "    To use ${cyanbold}ICPipeline${clear} to with your own private repos, your ${cyan}ICPipeline Workers${clear} will"
  echo "    need a valid token for authenticated retrieval of your repos -- in order to build and deploy them.  If your GitHub is public,"
  echo "    you can just skip the token."
  echo
  echo -e "--> You'll select whether to disable password authentication on your ${cyan}Worker${clear} containers (always highly recommended)."
  echo -e "    Note that key-based authentication is always configured on each ${cyan}Worker${clear}, so this choice is basically whether to have both."
  echo
  echo -e "--> You can optionally add network ports to your configuration.  This is if, for whatever reason, your ${cyan}ICPipeline Workers${clear}"
  echo "    may need to accept inbound network connections on ports other than our defaults:"
  echo -e "    ${blue}Port 22 (for SSH access) and port 8080 (for browser access to your deployed projects).${clear}"
  echo -e "    When this option comes up, just enter any additional port numbers you wish to make accessible on your ${cyan}ICPipeline Workers${clear}."
  echo
  echo -e "--> In ${graylight}Public Network Mode${clear}, you can add an optional IP range (CIDR format) to limit remote access to your ${cyan}ICPipeline Workers${clear}."
  echo -e "    You can define/limit inbound access to your ${cyan}Workers${clear} by IP address or class.  See the README for additional detail."
  echo
  echo -e "--> In ${graylight}Private Network Mode${clear}, you can choose whether to add a VPN for remote Worker access."
  echo -e "    At your option, installer will create a VPN connected directly into the private network where your ${cyan}Workers${clear} live."
  echo
  echo -e "--> Finally, you'll tell the installer how many ${cyan}Workers${clear} it should initially create."
  echo
  echo -e "When the installer completes, you'll be able to log right into your ${cyanbold}Pipeline Manager (ICPM) d'app${clear} on the ${magentabold}Internet Computer${clear}."
  echo -e "Your ${cyanbold}ICPipeline Workers${clear} will already be registered with your ${cyanbold}ICPM${clear}.  You'll see them there in your ${cyanbold}ICPM${clear} dashboard,"
  echo "ready and waiting for their first deployment assignments from you."
  echo

else

  echo
  echo "Alright then, the short version will do for today."

fi # end if longer preview was selected

echo
echo "Thanks."
echo

echo "If we're all on the same page ..."
pauseforuser
