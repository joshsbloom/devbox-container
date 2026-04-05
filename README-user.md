# DevBox User Guide — Hoffman2

## What is DevBox?

DevBox is a containerized development environment that runs on Hoffman2.
It packages a modern Linux system (Ubuntu 22.04) into a single file that
runs on Hoffman2's older OS without conflicts. You get R 4.5, Python 3.12,
VS Code, RStudio, JupyterLab, Claude Code, and Codex — all accessible from
your browser or terminal, with Intel MKL for fast linear algebra.

The container itself is read-only and shared by everyone in the group.
Your personal packages, environments, and settings live in `~/.devbox/`
on your home directory and persist across sessions.

---

## Quick start

### Step 1: Connect to Hoffman2

From your laptop's terminal (Mac: Terminal.app or iTerm; Windows: PowerShell
or WSL):

    ssh <user>@hoffman2.idre.ucla.edu

Replace `<user>` with your Hoffman2 username. This puts you on a **login
node** — a shared gateway machine. You should not run heavy computation
here; it's just for managing jobs and files.

**Tip:** Set up SSH keys so you don't have to type your password every time:
https://www.hoffman2.idre.ucla.edu/SBO/devel/About/FAQ/FAQ.html#set-up-ssh-public-key-authentication

### Step 2: Get the scripts (one-time)

    git clone https://github.com/joshsbloom/devbox-container.git ~/Local/devbox-container
    chmod +x ~/Local/devbox-container/launch-devbox.sh ~/Local/devbox-container/devbox-setup.sh
    mkdir -p ~/Local/bin
    ln -sf ~/Local/devbox-container/launch-devbox.sh ~/Local/bin/launch-devbox.sh
    ln -sf ~/Local/devbox-container/devbox-setup.sh ~/Local/bin/devbox-setup.sh

This clones the devbox repository into `~/Local/devbox-container` and
creates symlinks in `~/Local/bin` so the scripts are easy to run.

### Step 3: Set up your shell (one-time)

    echo 'export PATH="$HOME/Local/bin:$PATH"' >> ~/.bashrc
    echo 'module load singularity' >> ~/.bashrc
    source ~/.bashrc

These lines are appended to your `~/.bashrc`, which runs automatically
every time you open a new shell. This means you only need to do this once:
- `export PATH=...` — lets you type `launch-devbox.sh` instead of the
  full path `~/Local/bin/launch-devbox.sh`
- `module load singularity` — makes the `singularity` command available
  (it's not on Hoffman2's PATH by default)

The `source ~/.bashrc` applies the changes to your current session.

### Step 4: Get a compute node

    qrsh -l h_data=8G,h_rt=8:00:00 -pe shared 4

This requests an interactive session on a **compute node** — a machine
dedicated to your work. The flags mean:

- `h_data=8G` — 8 GB of memory per core (32 GB total with 4 cores)
- `h_rt=8:00:00` — up to 8 hours of **wall time**
- `-pe shared 4` — 4 CPU cores

**Wall time** is the real-world clock time your session is allowed to run.
After 8 hours, the scheduler kills your session — whether you're done or
not. It's called "wall time" because it's the time elapsed on a wall clock
(as opposed to CPU time, which only counts when the processor is actively
working).

You'll wait briefly in the queue, then your prompt will change to show the
compute node's name (e.g., `n7234`). **Note this name** — you'll need it
later for SSH tunneling.

### Step 5: Run first-time setup

    launch-devbox.sh setup

This creates your personal conda environment with R, Python, Node.js, and
core packages. It takes about 15-20 minutes on the first run. You'll see
progress as packages are downloaded and installed.

### Step 6: Start working

    launch-devbox.sh shell

You're now inside the devbox container with R, Python, and all your tools
available. Your prompt will show `(devbox)` to indicate you're in the
container environment.

To exit the container, type `exit` or press `Ctrl-d`.

**Next step:** Read the [Hoffman2 best practices guide](README-hoffman2.md)
to understand the filesystem layout and how to manage storage — especially
important to avoid filling your home directory quota.

---

## Available commands

Once setup is complete, these are the commands you'll use day-to-day.
All commands are run **on a compute node** (after `qrsh`):

    launch-devbox.sh shell          # Interactive shell
    launch-devbox.sh code-server    # VS Code in browser (port 8080)
    launch-devbox.sh rstudio        # RStudio in browser (port 8787)
    launch-devbox.sh jupyter        # JupyterLab in browser (port 8888)
    launch-devbox.sh claude         # Claude Code CLI
    launch-devbox.sh codex          # OpenAI Codex CLI
    launch-devbox.sh gpu-job        # Request a GPU node, then launch shell
    launch-devbox.sh exec <cmd>     # Run any command in the container

Run `launch-devbox.sh` with no arguments to see all options.

---

## Optional package profiles

The base setup gives you R, Python, Node.js, core data science packages
(numpy, pandas, scikit-learn, matplotlib, etc.), JupyterLab, and CLI tools
(Claude Code, Codex).

For domain-specific packages, install **profiles**. Profiles are additive —
you can add them at any time without reinstalling anything:

    launch-devbox.sh setup --with bioinfo    # pysam, scanpy, Bioconductor, snakemake
    launch-devbox.sh setup --with ml         # PyTorch with CUDA support
    launch-devbox.sh setup --with r-extra    # tidyverse, lme4, brms, Bioconductor, etc.
    launch-devbox.sh setup --with all        # everything

You can combine profiles in one command: `--with bioinfo,ml`

You can also install profiles during the initial setup:

    launch-devbox.sh setup --with all

To start over with a clean environment (run from a compute node):

    # Remove the existing environment (runs mamba inside the container)
    launch-devbox.sh exec mamba env remove -p ~/.devbox/conda/envs/devbox -y

    # Recreate with whichever profiles you want
    launch-devbox.sh setup --with bioinfo,ml

---

## Installing packages

You can install packages directly without rebuilding anything. Run these
commands from inside a devbox shell (`launch-devbox.sh shell`):

    # Conda / Mamba (recommended for most things)
    mamba install -n devbox -c conda-forge <package>
    mamba install -n devbox -c bioconda <package>

    # Python (PyPI) — use when a package isn't available via conda
    pip install <package>

    # R (CRAN)
    Rscript -e 'install.packages("qs2")'

    # R (Bioconductor)
    Rscript -e 'BiocManager::install("DESeq2")'

    # Node.js
    npm install -g <package>

All installed packages are stored in `~/.devbox/` and persist across sessions.
They are isolated from any R/Python/Node packages you may have installed
directly on Hoffman2 outside the container.

---

## SSH tunneling (for browser-based tools)

VS Code, RStudio, and JupyterLab run as web servers on a compute node.
Your laptop can't connect to compute nodes directly — it has to go through
the login node. An SSH tunnel creates this connection.

### The idea

    Your laptop  →  Hoffman2 login node  →  Compute node (n7234)
    localhost:8080    (passthrough)          code-server listening here

You tell SSH: "when I visit `localhost:8080` on my laptop, forward that
to port `8080` on compute node `n7234`, going through Hoffman2."

### Step by step

**1. Start the service on the compute node** (in your existing SSH session):

    launch-devbox.sh code-server

The script prints the exact tunnel command you need — just copy it:

    Compute node: n7234
    SSH tunnel:   ssh -L 8080:n7234:8080 <user>@hoffman2.idre.ucla.edu
    Open:         http://localhost:8080

**2. Open a NEW terminal on your laptop** and run the tunnel command:

    ssh -L 8080:n7234:8080 <user>@hoffman2.idre.ucla.edu

Replace `n7234` with whatever the script printed. This terminal must stay
open as long as you want to use the service — it's holding the tunnel open.

**3. Open your browser** and go to `http://localhost:8080`.

That's it. The browser talks to your laptop's port 8080, SSH forwards it
through the login node to the compute node, and code-server responds.

### Ports for each service

| Service      | Default port | URL                      |
|--------------|-------------|--------------------------|
| code-server  | 8080        | http://localhost:8080     |
| RStudio      | 8787        | http://localhost:8787     |
| JupyterLab   | 8888        | http://localhost:8888     |

If a port is in use (another user on the same node), change it:

    CODE_SERVER_PORT=8081 launch-devbox.sh code-server
    RSTUDIO_PORT=8788 launch-devbox.sh rstudio
    JUPYTER_PORT=8889 launch-devbox.sh jupyter

### Avoid typing your password every time

Set up SSH key authentication so you don't need a password for login or
tunneling. Follow Hoffman2's guide:
https://www.hoffman2.idre.ucla.edu/SBO/devel/About/FAQ/FAQ.html#set-up-ssh-public-key-authentication

### Simplify with SSH config

Add this to `~/.ssh/config` on your **laptop** to avoid typing the full
hostname every time:

    Host hoffman2
        HostName hoffman2.idre.ucla.edu
        User <your-username>
        ServerAliveInterval 60
        ServerAliveCountMax 3

Then tunneling becomes:

    ssh -L 8080:n7234:8080 hoffman2

### Multiple services at once

You can run multiple tunnels in one SSH connection:

    ssh -L 8080:n7234:8080 -L 8787:n7234:8787 -L 8888:n7234:8888 hoffman2

---

## Using tmux (recommended)

If your SSH connection drops (laptop closes, Wi-Fi blips), anything running
in that session dies — including code-server, RStudio, or a long computation.

**tmux** is a terminal multiplexer that keeps your sessions alive on the
compute node even after you disconnect. Think of it as a persistent
terminal session that lives on the server.

### Basic workflow

    # SSH to Hoffman2
    ssh hoffman2

    # Get a compute node
    qrsh -l h_data=8G,h_rt=8:00:00 -pe shared 4

    # Start a tmux session on the compute node
    tmux new -s devbox

    # Now launch your service inside tmux
    launch-devbox.sh code-server

If your SSH drops, reconnect and reattach:

    ssh hoffman2
    ssh n7234              # SSH directly to the same compute node
    tmux attach -t devbox  # reattach — everything is still running

### Running multiple services

Use tmux panes to run several services side by side:

    tmux new -s devbox

    # Pane 1: code-server
    launch-devbox.sh code-server

    # Ctrl-b %  (split vertically — creates a new pane to the right)
    # Pane 2: RStudio
    launch-devbox.sh rstudio

    # Ctrl-b "  (split horizontally — creates a new pane below)
    # Pane 3: interactive shell
    launch-devbox.sh shell

### Quick tmux reference

    tmux new -s devbox       # new session named "devbox"
    tmux attach -t devbox    # reattach to session
    tmux ls                  # list sessions

    Ctrl-b %                 # split pane vertically
    Ctrl-b "                 # split pane horizontally
    Ctrl-b arrow-key         # move between panes
    Ctrl-b d                 # detach (session keeps running in background)
    Ctrl-b x                 # kill current pane

**Important:** Run tmux on the compute node, not the login node. tmux on
the login node won't help because your `qrsh` session (and everything in
it) would still die if the connection drops.

---

## VS Code (code-server)

    # On compute node
    launch-devbox.sh code-server

    # Tunnel from laptop (in a new terminal)
    ssh -L 8080:<node>:8080 hoffman2

    # Open http://localhost:8080
    # Password is in ~/.config/code-server/config.yaml

code-server gives you the full VS Code experience in your browser. You can
install VS Code extensions, use the integrated terminal, and edit files
across your home, scratch, and project directories.

The launch script automatically configures code-server so that:
- The integrated terminal uses the devbox environment (R, Python, conda)
- The R extension points to the correct R binary
- The Python extension points to the correct Python interpreter

**Useful extensions to install** (from the code-server Extensions panel):
- R (REditorSupport.r) — R language support, linting, plot viewer
- Python (ms-python.python) — Python language support
- Jupyter — notebook support

**Note:** The R extension will auto-install `languageserver` — this is
already included in the devbox environment, so it should work immediately.

---

## RStudio Server

    # On compute node
    launch-devbox.sh rstudio

The script prints your login credentials:

    Username: <your-hoffman2-username>
    Password: <auto-generated random password>

    # Tunnel from laptop (in a new terminal)
    ssh -L 8787:<node>:8787 hoffman2

    # Open http://localhost:8787

RStudio uses the R installation from your conda environment, including all
packages installed via `install.packages()`, `BiocManager::install()`, or
`mamba install`.

To set a persistent password instead of a random one:

    RSTUDIO_PASSWORD=mypassword launch-devbox.sh rstudio

---

## Claude Code

Claude Code is an AI coding assistant that runs in your terminal.

### Authentication

Claude Code supports two auth methods:

**Option A: Subscription (Claude Pro/Max) — recommended**

    launch-devbox.sh shell

    # Inside the container
    claude

    # It will print a URL — open it on your laptop to authenticate
    # Credentials are saved to ~/.claude/ for future sessions

**Option B: API key**

    # Edit your env file
    vim ~/.devbox/env

    # Uncomment and add your key:
    export ANTHROPIC_API_KEY="sk-ant-your-key-here"

After first-time auth (either method), Claude Code caches credentials in
`~/.claude/` and won't ask again.

### Usage

    # Interactive mode
    launch-devbox.sh claude

    # One-shot command
    launch-devbox.sh claude "explain this Snakefile"

    # From inside a devbox shell
    claude

---

## Codex CLI

OpenAI's Codex CLI is another AI coding agent.

### Authentication

**Option A: ChatGPT subscription (Plus/Pro/Team)**

    launch-devbox.sh shell

    # Inside the container
    codex

    # It shows a device code + URL — open the URL on your laptop,
    # enter the code, and authenticate
    # Credentials are saved to ~/.codex/

**Option B: API key**

    vim ~/.devbox/env

    # Uncomment and add your key:
    export OPENAI_API_KEY="sk-your-key-here"

### Usage

    launch-devbox.sh codex

    # From inside a devbox shell
    codex

---

## GPU access

    # Request a GPU node interactively
    qrsh -l gpu,V100,h_data=8G,h_rt=8:00:00 -pe shared 4

    # Or let the script handle it
    GPU_TYPE=V100 launch-devbox.sh gpu-job

    # The script auto-detects GPUs — no extra flags needed
    launch-devbox.sh shell
    # → "[devbox] GPU detected — enabling --nv"

    # Verify inside the container
    nvidia-smi
    python -c "import torch; print(torch.cuda.get_device_name(0))"

Available GPU types on Hoffman2: P4, V100, A100, RTX2080Ti (check current
availability with the Hoffman2 documentation).

---

## Advanced topics

### Using a different conda environment

The default environment is called `devbox`. You can create additional
environments for specific projects:

    # Inside a devbox shell
    mamba create -n myproject python=3.11 pandas scikit-learn

    # Launch a shell using that environment
    DEVBOX_ENV=myproject launch-devbox.sh shell

Custom environments are stored alongside `devbox` in `~/.devbox/conda/envs/`
and are managed with standard conda/mamba commands (`conda activate`,
`mamba install -n myproject`, etc.).

### Shell customizations

Your personal shell settings (aliases, environment variables, etc.) go in
`~/.devbox/bashrc_user`. This file is sourced at the end of every devbox
shell session and is never overwritten by the launch script.

    vim ~/.devbox/bashrc_user

### Verbose mode

To see the underlying Singularity/Apptainer commands that devbox runs
(useful for learning or debugging):

    launch-devbox.sh --verbose shell

---

## Troubleshooting

### First-time slowness

The first time you run the container, Singularity/Apptainer may convert the
`.sif` file to a temporary sandbox. This can take a few minutes. To speed
this up, add these to your `~/.bashrc`:

    export SINGULARITY_TMPDIR=/u/scratch/$USER/singularity-tmp
    export SINGULARITY_CACHEDIR=/u/scratch/$USER/singularity-cache
    mkdir -p $SINGULARITY_TMPDIR $SINGULARITY_CACHEDIR

### Resetting your conda environment

If packages stop working, you get solver errors, or you just want a clean
slate, you can remove your conda environment and rebuild it. This does NOT
affect your files, projects, or API keys — only the installed packages.

Run these from a compute node:

    # 1. Remove the existing environment
    launch-devbox.sh exec mamba env remove -p ~/.devbox/conda/envs/devbox -y

    # 2. Recreate it (base packages only)
    launch-devbox.sh setup

    # 3. Re-add any profiles you had before
    launch-devbox.sh setup --with bioinfo,ml,r-extra

    # 4. Re-install any extra packages you added manually
    #    (check ~/.devbox/installed_profiles to see which profiles you had)

If you also want to clear the conda package cache (to free disk space):

    launch-devbox.sh exec conda clean -afy

To do a full reset of everything devbox-related (environments, settings,
caches — but NOT your API keys):

    rm -rf ~/.devbox/conda ~/.devbox/pip ~/.devbox/npm-global ~/.devbox/R/library
    launch-devbox.sh setup

### Isolation from host

The container is fully isolated from Hoffman2's native R/Python. Packages
installed via `module load R` on the host will NOT be visible inside the
container, and vice versa. This is intentional — it prevents version
conflicts and ensures reproducibility.

### Getting help

    launch-devbox.sh          # Shows all commands and options
    launch-devbox.sh --help   # Same thing

---

## File locations

Everything user-specific lives under `~/.devbox/`:

    ~/.devbox/
    ├── conda/envs/devbox/    # Your conda environment (R, Python, Node.js)
    ├── conda/envs/*/         # Additional conda environments (DEVBOX_ENV)
    ├── conda/pkgs/           # Conda package cache
    ├── R/library/            # R packages from install.packages()
    ├── R/Renviron            # R environment config
    ├── pip/                  # pip --user packages
    ├── npm-global/           # Global npm packages (Claude Code, Codex)
    ├── renv-cache/           # renv package cache
    ├── jupyter/              # Jupyter config and kernels
    ├── rstudio/              # RStudio Server state
    ├── bashrc                # Shell init file (auto-generated by launch script)
    ├── bashrc_user           # Your personal shell customizations (never overwritten)
    ├── installed_profiles    # Tracks which profiles have been installed
    ├── env                   # API keys (chmod 600)
    └── tmp/                  # Per-session temp directories
