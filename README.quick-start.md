### Welcome to ICPipeline

Warmest greetings to all IC folk.  We hope that ICPipeline will add value to your Internet Computer journey.  Your success is our success.

For new users, we recommend doing a test iteration of ICPipeline.  If you take the roughly-half-hour to do an install/uninstall of the simplest config, you'll know more than you'll get from reams of reading -- in terms of what ICPipeline is, what it does, and how it works.  The ability to wipe the slate clean, start fresh, iterate -- is a itself a key piece of the *why* of this framework.

A complete, running framework setup has a few moving pieces to be sure, but it's very flexible, disposable, ephemeral, you name it.  You can run one ICPipeline indefinitely.  Or run one per-project.  Or run it 'til something goes sideways, flush and repeat.  Whatever works, is the point, and the framework will do that with you.

You can reference our how-to playlists on YouTube at any time:

<a href="https://www.youtube.com/watch?v=9oMyTTDvHGw&list=PLUNN54d-q9QMYLekS2Ew9x2E6nwIOwUvT">Installing the Framework</a>

<a href="https://www.youtube.com/watch?v=CKc5dw0nqnI&list=PLUNN54d-q9QMgmv2QWExZWORqk1rtAyD2">Getting Started Using ICPipeline</a>


To do the recommended test installation, follow these steps.  You will need a cycles wallet with some cycles; your dedicated ICPM is a standard two-canister IC dapp.

1). Clone the complete framework and cd into the folder.  Note the `--recursive` flag, it's a modular framework structured into Git submodules:
```
git clone --recursive https://github.com/icpipeline-framework/icpipeline-complete-beta.git && cd icpipeline-complete
```

2). Run the installer:
```
./installer.sh
```

... and just follow the prompts from here.  "Clone and go" is the idea.  The installer does the work, and you choose options as you go.  This is a loose play-by-play:

a) First, read through the introductory/disclosure section at your pleasure.  Just \<ENTER\> a time or three to advance.
b) Next comes requirements verification -- if anything's missing on your machine, the installer will let you know.
c) GitHub Auth token: \<ENTER\> to skip past this for now, we'll come back to it later.
d) Enable password auth on your Workers: ENABLE, since this is just a test.
e) Additional ports: \<ENTER\> to skip for now.
f) Public vs Private Network Mode: choose PUBLIC for least possible friction, we'll just delete it anyway.
g) Ingress CIDR range: \<ENTER\> to skip for now.
h) Number of Workers: \<ENTER\> to accept the default of 2
i) Copy SSH key: \<ENTER\> to skip for now (we enabled password auth anyway).

And that's it.  The installer will take it from here.  When it completes in 5-8 minutes, you'll have:

1) Your dedicated Pipeline Manager canister dApp (ICPM), deployed on the Internet Computer.
2) Two containerized Workers, which will have automatically registered with your ICPM by the time you log in.
  
Your installer terminal window will display the URL to your ICPM dapp.  Paste that into a browser, use the default Manager Code to log in, where you'll be required to change to your own Manager Code.

Now might be a good time to look at that YT playlist if you haven't -- it walks you right through getting started with your ICPM dapp.
<a href="https://www.youtube.com/watch?v=DlOplFmLWSQ&list=PLUNN54d-q9QMRT441IdOEC0b6RXKJUqOe">ICPipeline: Getting Started on YouTube</a>

Please refer to the main README for more detailed information.  Reach out to us at any time if we can help you along on your IC journey.  We're on the same journey, and we'll probably pick your brain too.