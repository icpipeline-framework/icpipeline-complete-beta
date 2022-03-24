#!/bin/bash

# ANSI escapes for colored text outputs
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
bluebold='\033[1;34m'
bluelight='\033[1;34m'
purple='\033[0;35m'
purplelight='\033[1;35m'
magenta='\033[0;35m'
magentabold='\033[1;35m'
cyan='\033[0;36m'
cyanbold='\033[1;36m'
graydark='\033[1;30m'
graylight='\033[0;37m'
graylightbold='\033[1;37m'
# return text color to default
clear='\033[0m'

# e.g.
# echo -e "Make my text ${red}RED${clear}"

# handles input arguments so that
# user can type them in any order, case-neutral, when running the main installer,
# (which is the only point where users need to consider it in regular usage).
# likewise, args will uniformly trickle down, i.e. every script will simply
# pass along "$@" to any script it subsequently invokes, with each one invoking
# this here function right off the bat.
process_args () {
  # echo ":::::: PROCESS ARGS FUNCTION WAS INVOKED HERE ::::::"
  for arg in "${@}"
  do
    arg=$(echo $arg | tr 'a-z' 'A-Z')
    if [[ "INCLUDE" == $arg ]]; then
      include=true
    fi
    if [[ "IAM" == $arg ]]; then
      iam=true
    fi
    if [[ "FARGATE" == $arg ]]; then
      ecs_launch_type="FARGATE"
    elif [[ "EC2" == $arg ]]; then
      ecs_launch_type="EC2"
    fi
  done
}

# pause function to allow users time to follow along
# with onscreen info
pauseforuser(){
 read -s -n 1 -p "Press any key to proceed when ready..."
 echo
}

# uniform output when invalid user inputs are received.
# only fits single-level escape conditions ... i.e. break
invalid_response(){
  echo
  echo -e "${yellow}That's not a valid response for this option, please try again.${clear}" && break
}

#  spits a little caution animation to screen
swsh(){
  for i in {1..28}
  do
    echo -ne "<*>"
    sleep .015
  done
  echo ""
}
# swsh

greencheck(){
echo -e "${green}☑${clear}"
}