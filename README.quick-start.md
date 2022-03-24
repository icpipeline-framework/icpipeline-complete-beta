### Welcome to ICPipeline

It is highly recommended for new users to do a test iteration -- one build-and-destroy, end to end.  It's quick and painless, and it's the best way to get a real sense of what it does and how it works.

The framework necessarily has quite a few moving pieces, which makes it all the more important to know that you're not married to anything.. You're not stuck in a rigid, monolithic construct, because it's cake to just blow it away and start clean.

Doing so will A) help you get the feel of things, and B) acquaint you with how easy it is to roll back an installation.  The framework's flexibility, and the ability to simply "rewind", is very much a part of the overall value proposition.


To do the recommended test installation, follow these steps:


1). Clone the ICPipeline software, cd into the folder:
```
git clone --recursive https://github.com/icpipeline-framework/icpipeline-complete.git && cd icpipeline-complete
```

2). Run the installer:
```
./installer.sh
```

In a sense, that's all there is to it, because you just follow the prompts from here.  "Clone and go" is the idea, and we've tried hard to make it that way.  The installer does all the work, inviting you to choose options as you go.  Most of your input is front-loaded -- meaning that the  info-gathering comes near the top, and *then* it executes based on your selections.

First you'll read through the introductory/disclosure section, at your pleasure.  Just \<ENTER\> a time or three to advance.

Next come requirements verification, where the installer will confirm that the tools are present on your machine.  Pay attention here to your AWS profile.  The installer will display your profile information, which is important because your profile determines where the resources will be built, while providing the necessary AWS account permissions.  Truth be told, it will simplify matters if you have admin privileges.  Your profile needs to be able to build, manage and delete resources relating to VPC and ECS/Fargate.  And, depending on the options you select, VPN and EC2 resources may also come into play.  We're a small shop and we have not yet sorted out a detailed *least privilege* baseline.  Meantime, it will be a plus if you can pretty much swing the hammer in your AWS account.  

Other than that, the requirements will be givens for most IC folk -- Node, Docker, the Canister SDK, AWS CLI, Git.  One item most of you may not have is JQ (`brew install jq`), which is a lightweight JSON parser for bash.  ICPipeline is basically a tool for using other tools, and these are the tools.









The installer will first display some introductory disclosure information, and then proceed to system requirements verification.  Just review your screen outputs and press \<ENTER\> to proceed when ready.

To continue with a default, secure Private Network Mode, continue right here.  Or, for a quicker, easier Public Network Mode installation, skip down to that heading.


3). Here, we suggest taking time to review the installer's introduction, full disclosure, requirements verification, etc. -- there is plenty of useful onscreen information in the terminal window.  Pay particular attention to your AWS profile details, especially if you use multiple named profiles with the AWS CLI.  The installer reads from your profile and displays the relevant parts for your confirmation.  You'll need robust permissions in the AWS account (details below).  Likewise, you'll want your Workers' container infrastructure to land in the right account, region, AZ, etc.  It works well with multi-account AWS setups.  We do, so it's well-tested in that respect.

4). At the next pause, press `<ENTER>` to accept the default *Secure Network Mode*.
The installer will verify the remaining requirements on your system, printing its findings to screen.  If it detects anything missing, it will tell you and offer guidance.  Again, it's worth following along with your screen output.

5). The installer next displays a lists the remaining options you'll be need to select.  For the most part, these options pertain to the network architecture and security of your containerized Workers.  Now is a good time to pause and review this list, as each choice will materially affect your outcome.  If unsure about any of them, consult with a systems/network engineer on your team, or you can reach out to us at ICPipeline and we'll try to help.