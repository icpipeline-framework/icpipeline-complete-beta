# ICPipeline

Thanks for your interest in ICPipeline, a development catalyst for the Internet Computer (aka "the IC").  ICPipeline provides IC developers with better tools for collaboration, DevOps, CI/CD and more.  We think it will lower the barriers to entry for Internet Computer development, thereby helping to grow the IC development community.

The key reason for ICPipeline is that it provides IC builders with a backbone for pre-prod development (it deploys your IC canisters too).  It can be a game changer for those accustomed to having dev, QA, and staging environments.  If you have the sense of a gap between `dfx deploy` locally and `--network ic`, -- well, that rather large space in the SDLC is essentially the problem space that ICPipeline is aimed at.

This document's focus is the overall framework architecture and getting started with the installer.  Details about the individual components are in the their respective module READMEs

![icpipeline-complete-framework-overview.png](https://icpipeline.com/media/documentation/icpipeline-complete-framework-overview.png)
<p align="center" style="color:gray;font-size:14px;"><b>ICPipeline Complete Framework Overview</b></p>



To jump right into ICPipeline installation, just follow these steps.  Note that this is a more in-depth walkthrough, producing a secured, real-world ICPipeline implementation.  If you've already done the recommended test install in the quick-start README, this is a good place to pick up.

1). Clone the ICPipeline software (and cd into the top-level directory):
```
git clone --recursive https://github.com/icpipeline-framework/icpipeline-complete-beta.git
```
2). Run the installer:
```
./installer.sh
```
or the simple installer, which is less verbose and makes a bunch of choices for you.
```
./simple-install.sh
```

Read through the introductory output, and take note of the system requirements to be sure your machine has the required tools onboard.  You will additionally need a cycles wallet with ~8T cycles, since we're deploying your dedicated ICPM canister dapp as part of your installation.  The installer will verify your wallet and cycles along with the other requirements.

You should review your screen output -- the information is readable and useful.  Pay particular attention to your AWS profile details, especially if you use multiple named profiles with the AWS CLI.  The installer reads from your profile and displays the relevant parts for your confirmation.  You'll need robust permissions in the AWS account.  Likewise, you'll want your Workers' container infrastructure to land in the right account, region, AZ, etc.

Then press `<ENTER>` to proceed.

BTW the installer will prompt you if Docker isn't present *and* running.  If not, you'll have a chance to start it before continuing.  Do give it a moment to come all the way up.

3). ***Your GitHub auth token***
The first item you'll supply is a GitHub auth token.  If you plan to use this installation to deploy IC projects from your private GitHub repos, ICPipeline will need a token in order to authenticate when fetching your code.  Just follow the prompts to paste one in and confirm.  Or, if deploying from public GitHub repos, just <ENTER> to skip.  Note that the installer will take what you give it, we do not validate this particular input.  So please provide either a valid token or nothing at all.

4). ***Enable/Disable Password Auth***
Next up, you'll be asked whether to enable password authentication on your ICPipeline Workers.  Each Worker is a Docker on an Ubuntu base, and there's an *icpipeline* system user on each Worker.  Key-based authentication is always configured, so really this choice is whether to allow both login methods.  Key-based auth is highly recommended.  The installer generates a key pair, and the private key is placed conveniently in /resources  Password validation (if applicable) enforces only a six-character minimum length.

5). ***Customized Worker Ingress Ports*** (`<ENTER>` to skip)
Next, you can enable remote access to your Workers on additional ports (other than the default ports used by the framework itself).  This will vary depending on the requirements of your own IC project(s).  If your projects communicate on ports other than the defaults, this is where you can enter them.  Bear in mind that the installer simply creates and configures an AWS security group here (tagged "ICPipeline Worker Security Group" in your AWS console).  So direct adjustments are easy if the need should should arise.

6). ***Private vs Public Network Mode***
This one is the most significant choice you'll make during installation.  You're telling it whether to host your containerized Workers in a private network or a public network -- basically, whether or not they'll have public IP addresses (and all that that implies).  To be clear, your Workers are robustly networked in either case, each with its own out-facing, reachable network interface.  This is just whether they're *publicly* addressed or not.  Since this is "real world" installation that should be maximally secured, we're going with Private Network Mode.  Type and enter `PRIVATE`.  We'll add a VPN, so your privately-networked Workers will be fully reachable via SSH, browser etc.

7). ***Would You Like a VPN With That?***
Let's go ahead and add that VPN.  Type/enter `VPN' here.  The installer will leverage OpenVPN tools and AWS services to create an E2E VPN.  The client config file will be ready to go in /resources/vpn-client-config where you can't miss it.  No edits or fiddling necessary, just drop that into any OpenVPN-based client and your tunnel will nail right up, directly into your Worker network.

8). ***Fargate vs. ECS/EC2 Container Instances***
You can host your Worker Dockers on either Fargate (i.e. purely as-a-service), or in/on EC2 container instances.  Operationally speaking, the primary distinctions are in terms of cost efficiencies.  You should do the reading to determine what approach works best for you in the long run.  For now we'll go with Fargate.  Type and enter `FARGATE`.  That's unless you preference for container instances, it works great either way.  Note that if you do go with container instances, you'll need to consider stuff like containers-per-instance.  In our default sizing (that's both instances and individual containers), it's basically two containers per instance.

9). ***Number of Workers***
Enter the number of ICPipeline Workers you'd like the installer to create.  Again, reference the note above if using EC2 container instances.  If you select more Workers than your instances will accommodate, nothing will break.  But your Worker count may come up "short", since the instances can only hold what they can hold.

10). ***Copy SSH Key***
Lastly it will ask if you want to copy your Worker SSH key to the standard place in your home directory.  Either way.  It just asks before doing anything outside the project directly, with respect to your privacy.

And that's it.  The installer has what it needs to take it the rest of the way.  It's worth following along.  Your screen output is informative and explicit as it proceeds through the steps of your framework build.

First it will create the necessary network scaffolding in AWS -- VPC, subnet(s), security groups, route tables, etc. -- to support your Workers.

Then it `npm` builds and deploys your ICPM canister dapp to the Internet Computer.

Next, it swings back to AWS and adds container infrastructure (on the previous network infra) for your Worker Dockers.  It creates an ECS cluster, which is essentially the skeleton that your containers run on.  Then it builds your Worker image from the Dockerfile (and setup script) in your Worker module, and pushes the finished image to your private ECR repository.  Then it can run your Workers (however many you selected) from that image.  As your containers spin up, they'll automatically register with your ICPM dapp (by canister ID, which is encoded into your image).  By the time you get logged into ICPM, they'll already there, registered and ready take your task assignments from the ICPM dashboard.

When the installer is finished it will display the URL for your new ICPM.  Just paste that into a browser and follow the prompts.  It will take you through changing the default passcode, which is required as the first order of business.

By the time you logged into ICPM, your Workers will be up, registered and visible in your ICPM console.  Use the wizard to quickly set up your first Environment and Project (a demo Project is supplied).  Then you'll click "Deploy Now".  In the time your Worker takes to clone/build/deploy your project, it will available in a browser -- subject, of course, to network connectivity.  The ICPipeline Manager (ICPM) *README* explains browser access in conjunction with VPN and the ICPM access tools -- it is fairly straightforward and quite useable.

If you haven't checked our "Getting Started" YouTube playlists, you may find those helpful now:
<a href="https://www.youtube.com/watch?v=9oMyTTDvHGw&list=PLUNN54d-q9QMYLekS2Ew9x2E6nwIOwUvT">Installing the Framework</a>

<a href="https://www.youtube.com/watch?v=CKc5dw0nqnI&list=PLUNN54d-q9QMgmv2QWExZWORqk1rtAyD2">Getting Started Using ICPipeline</a>

For remote access to your Private Network Mode Workers, use the VPN and your Worker SSH key like so:

- VPN: Your VPN client config file is located in `/resources/vpn-client-config`.  Import the client config file (`icpipeline_vpn_client_config.ovpn`) into an OpenVPN-based client.  The file is ready to go.  The installer has already inserted the required client certificate, so no editing or tweaking required.  Once your AWS Client VPN Endpoint is fully up and available (you can verify/monitor in the AWS console), just click to connect.

- SSH: While connected to the VPN, SSH into any Worker using the private key generated by the installer.  Each Worker's IP address is displayed in ICPM.  Your SSH key is in /resources/worker-ssh-key, and (if you instructed the installer to copy it) it's also in your `~/.ssh` folder.  For instance:
```
ssh icpipeline@10.0.100.XX -i ~/.ssh/id_ed25519_icpipeline
```
In certain cases, your SSH-over-VPN connection may additionally act as a reverse tunnel for port-forwarded browser connections ... blahblahblah.  ICPM has nice buttons and it's worked out to be seamless without headaches for you.  Consult the ICPM *README* for a fuller explanation.

Here we basically revisit what's in the quick-start README just in case you haven't seen that.  This covers the simpler path to a public-networked minimum friction installation.

### To Continue With a Quick/Easy Public Network Mode Installation:
3). Select these options as the installer prompts you:
- `Type/enter "PUBLIC"` to override the default and select *Public Network Mode* installation.
- `Paste in your GitHub auth token` (probably unnecessary on this first pass, only needed to deploy from your private repos).
- `Type/enter "ENABLE"` to allow password authentication on your Workers (then you'll supply a password).
- Then just `<ENTER>` to skip past the remaining options.
  
4). When the installer completes, copy/paste the URL for your new ICPM into a browser, and follow the prompts.

By the time you've logged into ICPM, your two Workers will probably be registered in your ICPM console, ready to go (give them a moment if you don't see them at first).  Use the wizard to quickly set up a first Environment and Project (a demo Project is supplied), click "Deploy Now", and you're done.  In the time your Worker will take to clone/build/deploy, your project will available in a browser from anywhere.  This assumes network connectivity, of course.  But in this case (in Public Network Mode) your Workers are on a public network, each with its own public address, making them very highly available.

***

***Some Architectural Notes***

ICPipeline is comprised of component modules.  The GitHub is structured accordingly (as a parent repo and *submodules*), as follows:
- ***icpipeline-complete***: the main, top-level module.  Contains the installer code base, its modular helpers and admin tools for the framework.
- ***manager***: ICPipeline Manager (aka ICPM), the dashboard/console d'app for managing ICPipeline.  Each implementation has a dedicated ICPM.  It is cloned, built (via *npm*) and deployed to the IC during each installation.
- ***worker***: holds just a *Dockerfile* and its *setup.sh* script.  Together they build the containerized image for ICPipeline Workers (on an Ubuntu Linux base image).
- ***uplink***: the NodeJS *Uplink* module that runs *on* each Worker.  *Uplink* handles all *Worker*<>*ICPM* communications and interoperation.  *Uplink* is cloned onto each individual Worker container at runtime for freshness.

Individual modules are covered in detail by their respective *README*s.  Full documentation for the framework will also be published at <a href="https://icpipeline.com/" target="_blank">ICPipeline.com</a>.  We are a small team and documentation will be ongoing.

The diagram at the head of this document shows a thumbnail overview of an ICPipeline framework installation (in Private Network Mode specifically).  As you can see, it piggybacks certain *W2/cloud* resources, using them to underpin your network of containerized Internet Computer replica hosts.  That's how ICPipeline creates your multi-tiered CI/CD platform for the IC -- all yours in about a half-hour.  Just run the installer and start using it.

***General Info to Help You Get Started With ICPipeline***
ICPipeline offers straightforward setup/startup for new users.  It is built so you can simply clone the repo, run the installer, and you're done: with a working E2E framework that allows you to focus on your own projects.
 
Your preferences are entered during installation; just follow the prompts.  On completion, the installer will display the URL for your Pipeline Manager d'app (ICPM), which it has deployed on the Internet Computer.  The installer will also:
- build the Docker image for your Workers
- pushes the image to your private ECR registry in AWS
- run your containerized IC replica Workers (two by default, but as many as you tell it).  Each container will "phone home" on startup, registering itself automatically with your ICPM.

At your initial login to ICPM, you'll set up your authentication preferences, which include Internet Identity (highly recommended, not enforced).  And that's it; you can just start using the platform.  There's a sample project (it's just a copy of Dfinity's "Hello" IC starter project).  We suggest using that for your first deployment, just to get acquainted, but you don't have to (see the ICPM *README* for more detail).

You need to have the prerequisites installed (standard Node/React dev tools, see a detailed list below).  The installer verifies its requirements right at the top, and will try to guide you if anything is missing.  With requirements in order, installation should take 15-30 minutes (depending on your machine, network speed, etc.).

Your installation will in one of two *Network Modes*: *Private Network Mode*, or *Public Network Mode*.  Each has its own basic network architecture and overall security profile, mainly relating to your Worker replicas.  A detailed explanation is provided below, and that is worth a look before you decide.  In very general terms, a private network will generally be more secure, while a public network will be more accessible and convenient on the whole.

- But *Private Network Mode is still convenient*, if you choose the VPN option (the installer builds it, soup to nuts).
- And *Public Network Mode is still secure*, when you restrict remote access to only your IP address or range.

There are other options too, all explained below.  You can run a tight ship in either mode.

Please don't worry about getting everything perfect the first time out.  The entire framework can be rolled back very easily, to wipe the slate clean and start over.  As users ourselves, we love being able to *iterate*, just get the feel of things -- especially with new tools and lots of moving pieces (it's largely why we built this).  So there's no need to tiptoe around it:  forge ahead; make incorrect settings; try things; break stuff.  That is what it's here for.

Your working framework architecture will essentially straddle two environments:

- The Internet Computer (where your ICPM d'app is deployed)
- Your AWS account (where your containerized replicas Workers and their underlying infrastructure live)

During installation there's basically a third environment, i.e. your local machine.  It may be helpful to view the architecture in terms of all three main pieces.

***ICPipeline Installation Requirements***
ICPipeline is essentially a tool for using other tools, all or most of which you probably have already*.   Before installing ICPipeline, you should have these tools on your machine.
- NodeJS/NPM (recommend even-numbered Node ^16, NPM ^7)
- Dfinity's Canister SDK
- A DFX Identity and a cycles wallet hodling (sorry) at least 8T cycles (ICPM architecture is a standard two-canister setup)
- Docker Engine (installed *and* running at installation time)
- Git
- JQ (a lightweight JSON parser for bash; the one item most Node/React/IC devs may actually need to ```brew install``` for this)

*JQ is one item that Node/React/IC engineers may need to install.  Our installer needs JQ, and you can `brew install jq` in just a few seconds.  It's a great tool to have in any case.

***An Important Note About Private Network Mode With Optional VPN***

In Private Network Mode framework installations, your Worker Dockers are deployed to a private-networked VPC in AWS.  To be clear, this type of installation  does *not* require a VPN in order to function fully.  The VPN option is there strictly to make your Workers more easily accessible.  That said, VPN facilitates browser access as well as SSH (e.g. when browser access goes through a port-forwarded SSH tunnel, etc.).  So, while it's not technically necessary for a functioning framework, VPN is a really big plus, almost a no-brainer if you haven't made other arrangements for access, in Private Network Mode installations.  We think most users will want to take advantage of it.  We certainly do -- our installations include VPN every time.

**Shell Output and Pagination**
As a general rule, our scripts are chatty (we're just trying to keep you in the loop), and they appreciate a roomy terminal.

(This probably won't happen to you, but) wanting to be transparent with our fellow engineers, we generally print terminal outputs to screen.  But in certain cases, where output is verbose enough to force pagination, ergo user interaction (i.e. <ENTER> to page on through or Control-C to quit), we'll divert output to /dev/null.  However, because individual terminal/window setups vary widely, there's a degree of imprecision here (indeed, we actually came across it while using gigantic terminal fonts to make our demo videos).  Bottom line, if you encounter this -- that is to say, paginated output(s) to your terminal window requiring intervention to bypass -- it won't break anything but it's unintentional.  In the event, we'd suggest stretching your window as an immediate solve and, if you'll kindly pass the word along we'll fix, with our thanks.  Likewise, if better bash programmers than we have advice to offer, we are all ears.

***Some Additional Notes on Configuration Options***

**Network Mode Selection**
This is most significant installation choice you'll make.  Either Network Mode may suit your needs (depends on your circumstances and requirements).  In practical terms, the differences pertain mainly to the network architecture and security profile of your containerized ICPipeline Workers.  As such, in addition to remote administration of your Workers, Network Mode will also affect browser access to your deployed *dev* and *QA* projects (*stage* and *prod* tiers deploy to the IC, where they're unaffected by this setting).

*Network Mode* is a global, framework-level setting.  But remember that you're not limited to having just one ICPipeline.  There's no hard limit to the number of Workers, Environments, Projects and Users a single framework can handle (within reason -- it's early days and we're a small team, deep breath).  However, you may simply prefer to break things up -- by size range, category, client, team segmentation, whatever works.  Or, even give every project its own ICPipeline.  We think of this along similar lines to multi-account org hierarchies in the cloud -- a la the *account-per-VPC OU* approach now favored by most teams in AWS.  But we digress.
  

**Private Network Mode** (default): Worker containers are deployed into a private subnet, and have *only* private IP addresses.  Private networks are inherently very secure, but generally less convenient and accessible.

In Private Network Mode:
- Your "*ICPipeline VPC*" has two subnets: "*ICPipeline Public Subnet*" and "*ICPipeline Private Subnet*".
- Workers live in the private subnet (having private addresses only)
- Worker network egress (i.e. ICPM connectivity) is via an "*ICPipeline NAT Gateway*".
- The public subnet has an "*ICPipeline Internet Gateway*"
  - (providing in/outbound for the public subnet, outbound only for the private subnet.)

We should emphasize that, in Private Network Mode, *your Workers do not have public IP addresses at all*.  They're still network-enabled and fully functional, with connectivity to their ICPM mothership (Workers initiate all communications, outbound via NAT Gateway).  But, going the other way, Private Network Mode Workers are reachable *only* via VPN (a bastion/jump host will also work, but we haven't added that feature to the framework yet).

At your option, the ICPipeline installer will automatically create a VPN, connected directly into the private subnet where your Workers live. This one-click operation will enable easy remote access to your secured Worker fleet.  Be aware when choosing this option that the installer will download OpenVPN encryption tools to your machine.  That is, only with your express permission; confined inside your ICPipeline project folder; fully transparent and easily removable.


**Public Network Mode** (optional): Worker containers deploy into a public subnet in your ICPipeline VPC, each with its own public IP address.  You'll still have tools to secure them -- security group config; limited ingress by CIDR range; key-based authentication with password auth disabled -- and you'll have granular control over those things.  But, to be clear, in Public Network Mode your Workers will live on a *public* network, which is what it is.

In Public Network Mode:
- Your "*ICPipeline VPC*" has just one subnet: "*ICPipeline Public Subnet*".
- Workers live in the public (only) subnet, each with a dedicated *public* IP address.
- The public subnet has an "*ICPipeline Internet Gateway*", allowing both inbound and outbound traffic.

An optional *Ingress CIDR Range* can make your Public Network Mode implementation more secure. Enter an IP address or range in CIDR format, and your Workers will accept inbound requests *only* from that address or range -- all other inbound requests will be blocked.  This can be really effective from a security standpoint.  For instance, if you and/or your team work behind a NAT/WiFi router, enter that single address in CIDR notation (the full address followed by "/32"), and your Workers will be remotely accessible only from that location.  Just be aware that these restrictions will apply to all ports and protocols, including browser/http(s) access.

Happily, in whichever network mode you choose, your ICPipeline Worker containers have "real" network interfaces, so they act as normal network hosts.  We love Dockers.  But the native Docker network stack, less so.  We think it works better this way and we hope you agree.

There's something we should point out, with respect to the *Ingress CIDR Range* and *Worker Access by Port Number* configuration options.  All settings relating to both options, across the whole framework iteration, live in a single "*ICPipeline Worker Security Group*" in AWS.  The port rules are there; the source address restrictions (if any) are applied to each port rule; and that one security group is applied to every Worker (just yours, not anyone else's).  We mention this because it's handy to know -- in the event of a missed setting, inadvertent lockout, etc. -- that your fix is likely to be in that one security group.

**GitHub Auth Token**
In order to deploy *your* IC projects, ICPipeline will need to have access to your private repos in GitHub.  So you <a href="https://docs.github.com/en/enterprise-server@3.3/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token/" target="_blank">generate a token in GitHub</a>, paste it into the installer prompt (then confirm).  It is worthwhile to create a token specifically for this purpose, which is then easily revocable without affecting your overall GitHub access.

**Password Authentication (i.e disabling it!!)**
Key-based authentication is enabled and configured on every ICPipeline Worker.  So you're essentially deciding whether to have both varieties of authentication.  We think password auth should *always* be disabled, especially when it's this easy to do, but we leave it up to you. 

Each Worker has a preconfigured *icpipeline* Ubuntu system user account, which has (passwordless) sudo powers.  It's Linux and you can manage your users as you like.  But *icpipeline* is intended as the main login and admin user on your Worker systems.  If/when modifying your Workers' system accounts, be advised that constraints applied to *icpipeline* will likely cause breakage.  The action all happens in her home directory, and she really needs to be able to take care of business.

Each individual Worker generates its own hostkeys, and the *icpipeline* user's client key pair is the same on all your Workers (it's definitely *not* the same one as anyone else's Workers).  The client private key is placed in */resources/worker-ssh-key* by the installer.

**Number of Workers**
The installer needs to know how many Worker containers to stand up initially.  The default is two Workers.  We chose that number in order to give new users a clear first impression of the framework, with multiple Workers present.  But it's perfectly fine to start with one Worker, or as many as nine.  It is among our top priorities to incorporate more tools for adding/subtracting Workers on the fly.  In the meantime, please use your Docker/orchestration tools.  Any container you run from your ICPipeline Docker image will be a functioning Worker.  Worker administration will be purely point-and-click in ICPM, very soon.

**Adding a VPN to Your ICPipeline** (Private Network Mode only)
In the default Private Network Mode, the installer will offer to create a VPN, by which you can directly access your Worker containers via SSH.  Be aware when selecting this option that the installer will download encryption tools (Open VPN Easy-RSA) onto your machine.  It's non-invasive, all confined within the ICPipeline project directory (in the /resources subfolder), and removal is as simple as deleting the folder.  Your "Add VPN" selection will automate the following steps:
- Download and install OpenVPN's Easy-RSA from GitHub
- Create a local "CA" (certficate authority).  "CA" in quotes because these are self-signed certificates functioning, more or less, as public/private key pairs.
- Generate two required certificates (one "server", one "client") and their respective private keys.
- Import both certificates into AWS Certificate Manager
- Stand up a VPN Client Endpoint, using both imported certificates (please be patient here with AWS latency, over which we have no control)
- Configure routing and access authorization for the endpoint
- Download the endpoint's client configuration (.ovpn) file from AWS
- Prepare the client config file for actual use by injecting the client certificate/key into it
- Place the finished client config file in your /resources/vpn-client-config folder

Please allow the time it takes for AWS to stand up your *VPN Client Endpoint* (our tests didn't exceed 15-18 minutes, though we saw forum-thread anecdotes about multi-hour waits).  Note that this VPN delay doesn't prevent your ICPipeline from working in the interim.  The VPN give you remote SSH access to your Workers, which is not even part of most regular workflows.  ICPipeline is fully functional and ready to go in the meantime via ICPM, in a browser.

When your VPN Client Endpoint indicates *ready* state, just import the client config file (in /resources/vpn-client-config) into any OpenVPN-based client.  Then consult your ICPM dashboard for the private IP of any Worker, and connect.  All in all, it is fairly straightforward and it works well.

The installer takes the following steps to create your VPN:
- Clone OpenVPN's EasyRSA encryption (to your machine, in a subfolder of your ICPipeline project directory).
- Add/configure a local CA (faux certificate authority)
- Generate two certificates: one "server", one "client" (self-signed, really just key pairs in this context).
- Import both certificates into AWS Certificate Manager
- Create an AWS Client VPN Endpoint (using the two certificates imported above)
- Connect the new endpoint to your *ICPipeline Private Subnet*
- Add routes and authorization rules to VPN endpoint config
- Download VPN client config file via AWS API
- Inject our client certificate into the client config file, making it ready-to-use

VPN setup is straight by the book, step-by-step:

<a href="https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/client-authentication.html#mutual" target="_blank">AWS Docs for Creating and Hosting Certificates</a>


<a href="https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/cvpn-getting-started.html#cvpn-getting-started-certs" target="_blank">[AWS Docs for Client VPN Endpoint Setup</a>

FYI, EasyRSA is not invasive.  It uninstalls cleanly, by just deleting the folder (ICPipeline Reset takes care of it).  It has been our experience, over some years, that OpenVPN tools are excellent and trustworthy as a rule.

Anyway, the installer does the whole thing, printing to your screen so it's quite transparent.  Just import the auto-generated client config file (/resources/vpn-client-config/icpipeline_vpn_client_config.ovpn) into an OpenVPN-based client and connect to your VPN.  At this point you can SSH (using the private key referenced above) into any Worker on its *private* IP.  And you are running a very tight ship, security-wise.

Note that your AWS Client VPN Endpoint may (sometimes, inconsistently, grrr) take what seems like ages to come up.  The installer offers tips on how to monitor in AWS console.  To be clear, this latency does not affect your actual ICPipeline in the meantime.  The VPN is there for SSH access to your Workers, which is not even part of most regular workflows.  Your ICPipeline is fully operational and accessible (via ICPM in a browser) during the few minutes while your VPN endpoint is coming up.


**A Caveat Regarding VPN Client Software**
We extensively used both *TunnelBlick* and *AWS VPN Client* in testing, both with identical, predictable results (i.e. it works great).  However, for reasons we have yet to track down, OpenVPN's very own client (*OpenVPN Connect*) does not work.  It seems unable to resolve the endpoint's hostname -- even while the other clients work fine -- as do *dig*, *whois*, etc. from the same machine.  For reasons TBD at this time, that particular client app just doesn't want to connect and we recommend *AWS VPN Client* and/or *TunnelBlick* (they're both free).  Annoying, to be continued ...

**ICPipeline, AWS and Docker Infrastructure**
Nearing the approach of our release date and *very* late in the game, development-wise, we got a nasty surprise.  We had scoped 1.0 to use exclusively Fargate for container infrastructure.  Of the available options, Fargate represents the lowest friction and greatest flexibility -- essentially the smallest out-of-the-box footprint.  And it worked *beautifully*, across hundreds of iterations over several months.  Then one day we woke up and `dfx start` was a non-starter ... invoking thread "panic" errors, which we eventually traced back to the Linux kernel.  It turns out that Fargate uses one global "host OS" kernel, which you can't change or substitute, and which also happens to be *ancient* at 4.14.  And the SDK is in Rust/Cargo, which one day suddenly choked on the Fargate kernel version.

### ICPipeline Reset and Why It's Useful
If you end up installing ICPipeline only once -- that is, if you just install it, drop in your project(s), and use it for the long haul -- that's a win and we'll be very happy.  But keep in mind that you can undo any installation at any time -- quickly, completely, painlessly -- with ICPipeline Reset.  Taking an ICPipeline down (first export your *canister state* data, there's a button for that) is as easy as putting it up.  We think that's important for a number of reasons:

- Say you want to change things around.  Iterating, reps and do-overs are just good.  We get smarter by doing.
- Or something broke.  Or you hit a speed bump on an installer pass.  Technology happens, things break, especially when dealing with networks and numerous potential points of failure.
- You decide to go with *multiple* ICPipelines.  One public and one private, perhaps.  Or, *pipeline-per-project*.  Run as many pipelines as you like.  The point is that, at some point along the way, you'll want to have another go at something.
- Or, even if (sadly) you've decided that ICPipeline's not for you, and you just want to walk away.

The framework is as breakable, repeatable and disposable as you need it to be.  It comes down to flexibility.  To be fearless and try things.  To sort out how *ICPipeline* -- and even the *Internet Computer* itself -- can add the most value for you and your team.

We've found the reset tools to be pretty resilient.  I.e. if for any reason things are in partial or halfway states, just go ahead and run reset.  The output may be a little ungainly, throwing errors as it tries to delete things that were already deleted, etc.  But it won't hurt anything, and it generally does a pretty good job of mopping up.

***How Reset Works***
As mentioned above, your ICPipeline framework lives in two primary spaces -- three if you count your local filesystem.

As with installation, ICPipeline Reset entails just running the script and following the prompts.  Also like the installer, the main resetter script has plenty of help.  By executing one script, you actually invoke three.  Here's the breakdown:

**/resources/util/reset_installation_main.sh**
In order to reset, this is the script you actually run.  It directly handles the local side (restoring your ICPipeline project folder to install-ready state), and acts as a UI/workflow for the overall process (optionally calling the other resetters. etc).

**/manager/reset_installation_ic.sh**
This script is dynamically generated by the main resetter at the time of reset.  It stops and removes the Internet Computer canisters containing your ICPM d'app.  By running it you will permanently, irretrievably remove your ICPM deployment.  Any unspent cycles in the canisters will be redeposited in your cycles wallet.

**/resources/cloudconf/aws/reset_installation_aws.sh**
This script was dynamically generated at the time of installation.  It deletes every AWS asset created by that specific installer run.  Like canister removal, this is permanent.

(Both secondary resetters can alternately be run separately, at a later time, as you prefer.)


**Step-by-Step Reset**
Starting in the main ICPipeline project directory, first locate your main resetter script:

```
cd ./resources/util
```
Execute *reset_installation_main.sh*.  Run it from right here in /resources/util
```
./reset_installation_main.sh
```

Please take a moment to review the onscreen messaging, including caveats and warnings, before proceeding.  Then just follow the prompts.  Reset will do the following:
- It will first roll back your local project folder to its original state.
- Then it will proceeding with canister removal from the IC (first asking you to confirm again)
- Lastly it will kick off AWS reset (you confirm, again).

If your ICPipeline Fargate Cluster has any remaining containers still running, you'll need to confirm before Reset removes each container.  Be aware that Reset removes *ALL* containers from that cluster, indiscriminately.  In the (unlikely) event that you have *non-Worker* containers running on that cluster, *Reset does not know the difference*.  This is mostly why we ask you to confirm each one before destroying it.

When your ICPipeline Fargate Cluster is idle, with no running containers, Reset will proceed and delete all AWS resources* from that specific installer run.

**Itemized List of AWS Resources Created by the ICPipeline Installer**
Here's a list of all AWS resources in a complete framework.  Each item is created by the installer at runtime, and subsequently removed by Reset (if/when you run it).
- 1 VPC (tagged "ICPipeline VPC")
- 1 public subnet ("ICPipeline Public Subnet")
- 1 public subnet route table ("ICPipeline Public Subnet Route Table")
- 1 private subnet ("ICPipeline Private Subnet")
- 1 private subnet route table ("ICPipeline Public Subnet Route Table") [Private Network Mode only]
- 1 Internet Gateway ("ICPipeline Internet Gateway")
- 1 NAT Gateway ("ICPipeline NAT Gateway") [Private Network Mode only]
- 1 Elastic IP, allocated and assigned to NAT Gateway above [Private Network Mode only]
- 1 ECS Fargate cluster (named "icpipeline-cluster-\<installer session_random numeric suffix\>")
- 1 ECR repository (named "icpipeline-repo-\<installer session_random numeric suffix\>")
- 1 ECS task definition (named "icpw-taskdef-\<installer session_random numeric suffix\>")
- *n* Containerized Workers (tasks [i.e. Dockers] hosted in the Fargate cluster)
- 1 Security Group (applied to each Worker container)

Note that ECS/ECR resource names for a given install are appended with matching numeric *session_random*.  It's a useful eyeball check when tying things together in the console or CLI.

Additionally, if the installer added a optional VPN
- 1 Client VPN Endpoint
- 2 Certificates (one client, one server -- generated locally, imported into AWS ACM)

\*ICPipeline Reset deletes every AWS resource generated by a specified installer run, with a single annoying exception.  It's not that we skipped over it.  The AWS CLI/API, as far as we can tell, has no known method for *completely* removing an ECS task definition.  It can *deregister revisions* of task definitions, which Reset does in this case.  But that revisionless husk of a task definition is left to your attention in the AWS console.  It's not a billable resource, just annoying.  <a href="https://awscli.amazonaws.com/v2/documentation/api/latest/reference/ecs/deregister-task-definition.html" target="_blank">Per the AWS documentation</a> (see the first gray "Note" near the top).  If you happen to know a method for this that you'd kindly share, we will get it right in here.


### On the Internet Computer, Security and Scalability are Not a Thing 
In order to deliver a platform with a respectable security profile, we needed to jump through some hoops, and we feel good about that.  But we should point out that *ALL* those hoops are on the *W2* side, where our replica *Workers* live.  For ICPM (and your deployed projects) on the IC, there simply are no such hoops, *because the Internet Computer*.  Simply deploy to the IC, with no headaches attached.  It seems very obvious to say.  But building this framework, directly juxtaposing both sides, has really brought it home.  And the thing is, it's *equally* true for Mom-and-Pops, *unicorn* tech startups and Fortune 100 enterprises.  To be sure folks, *this* is what *really* matters here.  We're not saying the IC will be running "*Meta*" (sigh) tomorrow; we're saying the paradigms will hold, down the road when the time comes.

### Troubleshooting Installation Quirks
We think ICPipeline, including the installer, is fairly stable and predictable.  That said, this is an early-lifecycle project, and there are some factors beyond our control.
The installer generates three log files, one each for Node/NPM, DFX and the IC, and AWS.  After the installer runs, your /installer-logs folder will contain

- *npm.build.log*
- *dfx.build.log*
- *aws.build.log*

Any or all these logs may help with troubleshooting, depending on what's causing the trouble.  They pretty much just capture stdio, AWS CLI output and so on.

#### Cross-Browser Compatibility and the Manager D'app
The ICPM frontend is essentially a React app with Material UI (MUI).  As such, it should be widely browser-compliant, including mobile.  Our testing was mostly limited to Chrome, Firefox and Safari.  But it's a React app, as far as your browser is concerned.

#### Usage Notes

**Paths in the Code Base**
ICPipeline invokes system utilities and other binaries uniformly by name, not by their full paths -- e.g. "*dfx*" rather than "*/usr/local/bin/dfx*".  We weren't careless about it; rather, we wanted avoid tripping on path discrepancies between end-user systems.  So $PATH is your friend, the first thing to check if "command not found" quirks occur.  Or you may, of course, just add your own paths in the code.

**Git Repo Structure**
As mentioned above, the ICPipeline "complete" git repo is structured into submodules.  We suggest that you browse through the folders, verify completeness (Appendix A is a complete assets manifest), and get a sense of things.  It's particularly worthwhile to review the header information in the main installer script (installer.sh).  There's a lot 'splaining in there, accompanying the setup of the core variables, etc.  That header section contains a lot of architecture-related items (e.g. IP addressing, etc.), and it should be informative to take a look.
  
**Cross-Platform Useability:**
We are a Mac shop here at ICPipeline.  Realistically speaking, this is MacOS software.  Linux (Ubuntu) is the foundation of every ICPipeline Worker, and the code base is not a long way from broad *nix friendliness.  That said, we want to be clear that we code, and test, on Macs.

**Windows:**: if you're running Windows, we should mention that ... well, we are not.  While we don't know of specific reasons (beyond the obvious ones) why ICPipeline shouldn't be adaptable to your purposes, we don't make any promises.  However, if you should decide to take up this flag, your input is welcome, and we will try to keep your priorities in the mix.

**Authors' Note**
With ICPipeline, we've tried to write something useful, in the hope and expectation that others may contribute and improve it.  To that end, the code is well-commented, naming conventions are verbose and descriptive, etc. etc.  If ICPipeline turns out to be useful enough that others want to invest their time in it, they should find the breadcrumb trail to be pretty thick.

**Disclaimer**
This comes direct from the MIT license, whose terms apply to this release:

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

**Pipeline Manager and Your Data**
Your Pipeline Manager d'app accrues data during normal use.  Your projects, environments, deployments, logs, etc. all exist as data objects in Pipeline Manager, which stores them on the Internet Computer blockchain.  On one hand, it's just workflow metadata, the loss of which won't put you out of business.  But, on the other hand, it's your workflow metadata -- it's the structure, history and who-did-what-when in your development framework.  ICPipeline collects/accrues *only* data that is relevant to its own operation.  We collect the names of your projects, environments, canisters, principals, etc. because the platform needs them to function.  We do *not* poke around *in* your projects, take copies of your code, or anything like that.  In any case, data stewardship is a core value with us; we respect your privacy, and we *really* don't want to be that guy who lost your data.

ICPipeline stores your data as *stable* variables in IC *canister state* (in the *icpm* canister specifically).  *Stable* data are maximally persistent on the IC.  This means your data will remain intact through upgrades/updates to the underlying canister software, i.e. your Pipeline Manager itself.  Likewise, the Dfinity team is always enhancing and refining the IC's *orthogonal* data persistence.  That said, this is not fool-proof, and a mistyped command can still result in irretrievable data loss.  So, before performing upgrades, modifications or re-deployments of your Pipeline Manager (or any) d'app, please take time to familiarize yourself with the rules, behaviors and best practices outlined in <a href="https://sdk.dfinity.org/docs/developers-guide/install-upgrade-remove.html" target="_blank">Dfinity's authoritative documentation</a>.

**ICPipeline and Your AWS Bill**
ICPipeline Workers are Dockers, and AWS is just one place to run them.  For ICPipeline *\<1.0*, we opted for Fargate.  So the ICPipeline installer creates a Fargate cluster in your AWS account.  From a billing standpoint, a Fargate cluster kind of like a VPC -- it's *free*, so to speak, and you pay for what you run *in/on* it.  ECS also has EC2-based container hosting, but if you go that route, you pay for the instances whether you have containers running or not.

**Canisters, Cycles, Identities and Wallets on the Internet Computer**
Cycles are the *gas* of the Internet Computer blockchain.  And because your ICPipeline Manager (ICPM) is itself an actual canister d'app running on the Internet Computer, you'll need a wallet with some cycles in order to build and operate it.


The following check is optional.  When you run the ICPipeline installer, it will verify your *dfx identity*, your *cycles wallet* and your balance in cycles.  It will offer guidance if it finds (rather, doesn't find) anything missing.

When you run this command from your terminal: `dfx wallet --network ic balance`

...you should see something like the following output: `18035485094038 cycles.`

 That should be a number at least thirteen digits in length, meaning in the trillions (*yes, with a T, as in 1000000000000, and you need at least eight of them*).  If you start out with some cycles in your wallet, you'll be good to go -- this part of your ICPipeline setup should be seamless.  Otherwise read on, and we'll point you in the right direction.

Many engineers are somewhere along this learning curve.  Dfinity's first-party documentation is very good, and we cannot overstate how worthwhile it is to do the reading.  If you haven't reviewed <a href="https://smartcontracts.org/docs/quickstart/network-quickstart.html" target="_blank">Dfinity's quick-start instructions</a>, you should definitely do so.  In addition to becoming much smarter, you'll find resources in place that really help take the sting out of this whole process.  Dfinity even makes cycles available at no charge -- via the <a href="https://faucet.dfinity.org" target="_blank">Cycles Faucet</a> -- for developers interested in the Internet Computer.  Cycles can be acquired for cheap or free, and that is but one reason to *rt\*m* if you're relatively new to the space.

**Docker-Related Items**
ICPipeline leverages Docker's multi-architecture support (via Docker BuildKit/"buildx").  This is mainly so ICPipeline supports Mac users with M1 processors -- aka "Apple Silicon".  This is seamless for Intel/Mac users, aside from one checkbox in your Docker Desktop app (assuming that you use Docker Desktop).  In order to interact with your local ICPipeline Docker images in Docker Desktop, enable Docker's "Virtualization Framework" in your Docker Desktop preferences, as follows:
- Select Preferences at upper right (click the "gear" icon)
- Select "Experimental Features" in left-side column nav
- Check the "Use the new Virtualization Framework" checkbox.

Now your (local) ICPipeline images, containers, etc. will appear normally in your Docker Desktop.

Appendix A: Assets Manifest

Top-Level Directory:
Files:
- install_icpipeline.sh (main installer script)
- icpm_network_install.sh (canister installation of Manager d'app)
- create_network_infra_aws.sh (creates aws infrastructure)
- ascii_logo_b64.txt (logo display, non-essential)
- .gitignore (important because each execution creates additional assets that shouldn't get into git)
- .gitmodules
  Directories:
  - /cloudconf
  - /cloudconf/aws (only _cloudconf_ in use at the moment)
  - /installer-logs (empty to start, populates with logs when you run the installer)
  - Module Directories:
    - /manager
    - /uplink
    - /worker-docker


#### Operating Costs
ICPipeline isn't expensive to operate.

The most significant cost factor in a real-world implementation, by far, will be container costs, i.e. hourly per-container rates for running containers.  We settled on Fargate a practical/practicable option.  We'll say again that A) Dockers are Dockers, and all that that implies; and B) there's no reason why Workers must be Dockers.  But on this first pass, we think Fargate is a solid, practical/practicable choice.  With Fargate, only running containers are billable, which is to say that your "ICPipeline Fargate Cluster" is free when there are no containers running in it.

The installer script contains two variables that provide control over container sizing -- ergo pricing, which is in direct, linear proportion to allocated CPU and memory.  We considered adding more choices to the installer UI.  But we preferred not to add clutter there and went this way instead.  You know what you're doing.

This cost is best viewed in "Worker hours": 1 Worker hour = the cost to run 1 Worker container for 1 hour.  A "Worker day", same idea * 24.

**Worker Container Costs (in "Nickels and Dimes")**
With acknowledgement of our inbuilt bias, as Americans who reflexively think in USD, we've found "nickels" and "dimes" to be handy rules of thumb.  As it happens, they align closely with the real-world incremental costs of operating Workers as Fargate containers.  Our default container size is (2048 CPU units, 4096 RAM in bytes).  As Dockers go, that's fairly large, but not huge.  And, in most AWS regions, it costs 9.8 cents/hour to run one on Fargate.  We also did many test builds with Workers at half that size (i.e. 1024 CPU, 2048 RAM).  That size works fine too, but "nickel-sized" Workers were just ...slower.  Smaller sizing may work fine for you, depending on your requirements.

By no means do we equate "nickels and dimes" with *cheap*.  The numbers, in either size, can really pile up.  At the larger size (to state the obvious), Workers cost nearly two and a half bucks a day to run, *each*.  Extrapolate that out over a fleet of Workers, for weeks into months, and you get the point.

Certainly there are cheaper ways to run containers.  We chose Fargate as merely the most practical and cost-effective way to *bootstrap* a container platform out of thin air.

To be sure, enhanced Worker/container management is (mixed metaphor alert) the next big-ticket item on our roadmap.  We will deliver the tools to start, stop, pause, sleep, duplicate, etc. your Workers, using only the buttons in your ICPM.  We are especially excited about this next phase, because the concepts and the R&D all overlap directly into moment-in-time canister-state snapshots; state replication across multiple environments; exports, off-site backups and HADR; and so forth.  Stay tuned because we intend to turn this around rapidly, *as long as we can pay our bills while we do it*.

**VPN Costs**
If you opt for the installer's *Add a VPN* option, those incremental costs will fall into a distant second place to your container costs.  We use an AWS *Client VPN Endpoint*, which the installer *associates* with your "ICPipeline Private Subnet".  Cost-wise, it works like so:
- The endpoint itself is "free".
- The subnet association costs ten cents per hour (this is the only *round-the-clock* cost associated with the VPN).
- Each active client connection (i.e. each user connected at a given time) costs five cents per hour.

So, it's more nickels and dimes, and these can add up too ... but it's not much, really.  Just admonish your teammates to disconnect (!!) from the VPN when they unplug.  Unless you're a really big shop, these costs remain at very manageable levels.

**Bandwidth/Throughput Costs**
The only other real cost factor is AWS bandwidth.  It can vary, we won't parse out every detail here, and common sense applies.  The Git repos aren't gigantic, they don't contain any multimedia or other multi-GB bandwidth eaters.  Neither does normal use ICPM in the browser, which is uniformly lightweight, network-wise.  All our testing (many hundreds of E2E builds, deployments, II integrations, QAs, epic fails, etc.) consumed *free-tier* levels of bandwidth.

With respect to AWS's bandwidth and other incremental charges: if your platform is *getting business done and accomplishing the work* necessary for these fees to really scale, they are usually symptoms of good fortune and therefore very manageable.  That's subjective and we make no warranties, but experience proves it out time and again.  *Just don't leave the lights on, because that's how they'll get you*.

#### Looking Ahead
We really hope you like ICPipeline and find that it adds value -- because your interest and engagement will create the opportunity for us to execute our roadmap.  The near-term will include:
- Transparent dollars-to-cycles administration (i.e. near-zero friction in the *crypto* layer for engineers focused on the tech).
- Cloud-agnostic, i.e. additional ports for Azure, GCP, Serverless Framework.
- GUI installer frontend (though we can't say we hate the shell/CLI).
- Backup and restore; snapshots; ability to preserve and replicate canister state.
- HADR, governance and compliance.

