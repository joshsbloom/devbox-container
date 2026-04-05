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

## Quick start

    # 1. SSH to Hoffman2
    ssh <user>@hoffman2.idre.ucla.edu

    # 2. Copy the scripts to your ~/bin (one-time)
    mkdir -p ~/bin
    cp /u/project/kruglyak/PUBLIC_SHARED/containers/launch-devbox.sh ~/bin/
    cp /u/project/kruglyak/PUBLIC_SHARED/containers/devbox-setup.sh ~/bin/
    chmod +x ~/bin/launch-devbox.sh ~/bin/devbox-setup.sh

    # 3. Add module load to your bashrc (one-time)
    echo 'module load singularity' >> ~/.bashrc
    source ~/.bashrc

    # 4. Run first-time setup (creates your conda environment, ~15-20 min)
    #    Must be run on a login node (needs internet to download packages)
    ~/bin/launch-devbox.sh setup

    # 5. Get onto a compute node
    qrsh -l h_data=16G,h_rt=4:00:00 -pe shared 4

    # 6. Start working
    ~/bin/launch-devbox.sh shell

## Available commands

    ~/bin/launch-devbox.sh setup          # First-time setup
    ~/bin/launch-devbox.sh shell          # Interactive shell
    ~/bin/launch-devbox.sh code-server    # VS Code in browser (port 8080)
    ~/bin/launch-devbox.sh rstudio        # RStudio in browser (port 8787)
    ~/bin/launch-devbox.sh jupyter        # JupyterLab in browser (port 8888)
    ~/bin/launch-devbox.sh claude         # Claude Code CLI
    ~/bin/launch-devbox.sh codex          # OpenAI Codex CLI
    ~/bin/launch-devbox.sh gpu-job        # Request a GPU node, then launch shell
    ~/bin/launch-devbox.sh exec <cmd>     # Run any command in the container

## Installing packages

No container rebuild needed — just install directly:

    # Conda / Mamba (recommended for most things)
    mamba install -n devbox -c conda-forge <package>
    mamba install -n devbox -c bioconda <package>

    # Python (PyPI)
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

## GPU access

    # Request a GPU node interactively
    qrsh -l gpu,V100,h_data=16G,h_rt=4:00:00 -pe shared 4

    # Or let the script handle it
    GPU_TYPE=V100 ~/bin/launch-devbox.sh gpu-job

    # The script auto-detects GPUs — no extra flags needed
    ~/bin/launch-devbox.sh shell
    # → "[devbox] GPU detected — enabling --nv"

    # Verify inside the container
    nvidia-smi
    python -c "import torch; print(torch.cuda.get_device_name(0))"

Available GPU types on Hoffman2: P4, V100, A100, RTX2080Ti (check current
availability with the Hoffman2 documentation).

---

## SSH tunneling (for browser-based tools)

When you run code-server, RStudio, or JupyterLab on a compute node, you
need an SSH tunnel from your laptop through the login node to the compute
node. Your laptop cannot reach compute nodes directly.

### How it works

    Your laptop  →  Hoffman2 login node  →  Compute node (n7234)
    localhost:8080    (passthrough)          code-server listening here

### Step by step

**1. Start the service on the compute node:**

    # On the compute node (after qrsh)
    ~/bin/launch-devbox.sh code-server

The script prints the tunnel command you need:

    Compute node: n7234
    SSH tunnel:   ssh -L 8080:n7234:8080 <user>@hoffman2.idre.ucla.edu
    Open:         http://localhost:8080

**2. Open the tunnel from your laptop** (in a NEW terminal):

    ssh -L 8080:n7234:8080 <user>@hoffman2.idre.ucla.edu

Replace `n7234` with whatever the script printed. This terminal must
stay open as long as you want to use the service.

**3. Open your browser** and go to `http://localhost:8080`.

### Ports for each service

| Service      | Default port | URL                      |
|--------------|-------------|--------------------------|
| code-server  | 8080        | http://localhost:8080     |
| RStudio      | 8787        | http://localhost:8787     |
| JupyterLab   | 8888        | http://localhost:8888     |

If a port is in use (another user on the same node), change it:

    CODE_SERVER_PORT=8081 ~/bin/launch-devbox.sh code-server
    RSTUDIO_PORT=8788 ~/bin/launch-devbox.sh rstudio
    JUPYTER_PORT=8889 ~/bin/launch-devbox.sh jupyter

### Simplify with SSH config

Add this to `~/.ssh/config` on your **laptop** to avoid typing the full
SSH command every time:

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

Run tmux on the **compute node** so your sessions survive SSH disconnects.
If your laptop closes or the connection drops, everything keeps running
and you can reattach.

### Basic workflow

    # SSH to Hoffman2
    ssh hoffman2

    # Get a compute node
    qrsh -l h_data=16G,h_rt=8:00:00 -pe shared 4

    # Start tmux on the compute node
    tmux new -s devbox

    # Launch your service inside tmux
    ~/bin/launch-devbox.sh code-server

If your SSH drops, reconnect and reattach:

    ssh hoffman2
    ssh n7234              # same compute node (note the name beforehand)
    tmux attach -t devbox

### Running multiple services

Use tmux panes to run several services at once:

    tmux new -s devbox

    # Pane 1: code-server
    ~/bin/launch-devbox.sh code-server

    # Ctrl-b %  (split vertically)
    # Pane 2: RStudio
    ~/bin/launch-devbox.sh rstudio

    # Ctrl-b "  (split horizontally)
    # Pane 3: interactive shell
    ~/bin/launch-devbox.sh shell

### Quick tmux reference

    tmux new -s devbox       # new session named "devbox"
    tmux attach -t devbox    # reattach to session
    tmux ls                  # list sessions

    Ctrl-b %                 # split pane vertically
    Ctrl-b "                 # split pane horizontally
    Ctrl-b arrow-key         # move between panes
    Ctrl-b d                 # detach (session keeps running)
    Ctrl-b x                 # kill current pane

**Important:** Run tmux on the compute node, not the login node. tmux on
the login node won't help because your `qrsh` session (and everything in
it) would still die if the connection drops.

---

## VS Code (code-server)

    # On compute node
    ~/bin/launch-devbox.sh code-server

    # Tunnel from laptop
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
    ~/bin/launch-devbox.sh rstudio

The script prints your login credentials:

    Username: <your-hoffman2-username>
    Password: <auto-generated random password>

    # Tunnel from laptop
    ssh -L 8787:<node>:8787 hoffman2

    # Open http://localhost:8787

RStudio uses the R installation from your conda environment, including all
packages installed via `install.packages()`, `BiocManager::install()`, or
`mamba install`.

To set a persistent password instead of a random one:

    RSTUDIO_PASSWORD=mypassword ~/bin/launch-devbox.sh rstudio

---

## Claude Code

Claude Code is an AI coding assistant that runs in your terminal. It
requires internet access, so it works best from a **login node** (compute
nodes on Hoffman2 typically do not have outbound internet).

### Authentication

Claude Code supports two auth methods:

**Option A: Subscription (Claude Pro/Max) — recommended**

    # On a login node (has internet)
    ~/bin/launch-devbox.sh shell

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
    ~/bin/launch-devbox.sh claude

    # One-shot command
    ~/bin/launch-devbox.sh claude "explain this Snakefile"

    # From inside a devbox shell
    claude

---

## Codex CLI

OpenAI's Codex CLI is another AI coding agent. Like Claude Code, it
requires internet access.

### Authentication

**Option A: ChatGPT subscription (Plus/Pro/Team)**

    # On a login node
    ~/bin/launch-devbox.sh shell

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

    ~/bin/launch-devbox.sh codex

    # From inside a devbox shell
    codex

---

## Important notes

### Internet access

Hoffman2 compute nodes generally do NOT have outbound internet. This means:

- **Works on compute nodes:** code-server, RStudio, JupyterLab, R, Python,
  Snakemake — anything that doesn't need to call an external API
- **Needs login node:** Claude Code, Codex CLI, `pip install` from PyPI,
  `mamba install` from conda-forge, `install.packages()` from CRAN

To install packages, do it from a login node first, then switch to a
compute node for your actual work.

### First-time slowness

The first time you run the container, Singularity/Apptainer may convert the
`.sif` file to a temporary sandbox. This can take a few minutes. To speed
this up, add these to your `~/.bashrc`:

    export SINGULARITY_TMPDIR=/u/scratch/$USER/singularity-tmp
    export SINGULARITY_CACHEDIR=/u/scratch/$USER/singularity-cache
    mkdir -p $SINGULARITY_TMPDIR $SINGULARITY_CACHEDIR

### File locations

Everything user-specific lives under `~/.devbox/`:

    ~/.devbox/
    ├── conda/envs/devbox/    # Your conda environment (R, Python, Node.js)
    ├── conda/pkgs/           # Conda package cache
    ├── R/library/            # R packages from install.packages()
    ├── R/Renviron            # R environment config
    ├── pip/                  # pip --user packages
    ├── npm-global/           # Global npm packages (Claude Code, Codex)
    ├── renv-cache/           # renv package cache
    ├── jupyter/              # Jupyter config and kernels
    ├── rstudio/              # RStudio Server state
    ├── bashrc                # Shell init file (auto-generated by launch script)
    ├── env                   # API keys (chmod 600)
    └── tmp/                  # Per-session temp directories

### Isolation from host

The container is fully isolated from Hoffman2's native R/Python. Packages
installed via `module load R` on the host will NOT be visible inside the
container, and vice versa. This is intentional — it prevents version
conflicts and ensures reproducibility.

### Rebuilding your environment

If your conda environment gets corrupted or you want a fresh start:

    # Remove the old environment
    mamba env remove -p ~/.devbox/conda/envs/devbox

    # Re-run setup
    ~/bin/launch-devbox.sh setup

### Getting help

    ~/bin/launch-devbox.sh          # Shows all commands and options
    ~/bin/launch-devbox.sh --help   # Same thing
