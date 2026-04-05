# DevBox

A portable, GPU-enabled development environment for HPC clusters.

DevBox packages VS Code, RStudio, JupyterLab, Claude Code, Codex, R, Python,
and a full bioinformatics stack into a containerized setup that runs on
clusters with outdated operating systems — no root access required.

## Why

HPC clusters run old enterprise Linux (CentOS 7, RHEL 7) with libraries too
ancient for modern tools. Users can't upgrade the OS or install system
packages. DevBox solves this with two layers: an Apptainer container provides
a modern Ubuntu base with system libraries, and conda environments on the
user's home directory provide all the actual software. Users can freely
install and update R, Python, and Node.js packages without rebuilding the
container or needing admin help.

## How it works

```
┌─────────────────────────────────────────────────────────────┐
│  Your packages (conda env on $HOME — freely customizable)   │
│  R 4.5 · Python 3.12 · Node.js 20 · PyTorch · tidyverse    │
│  Bioconductor · Claude Code · Codex · Snakemake · Jupyter   │
├─────────────────────────────────────────────────────────────┤
│  Container (.sif — read-only, shared by all users)          │
│  Ubuntu 22.04 · CUDA 12.4 · system libs · build toolchain  │
│  code-server · RStudio Server · Miniforge                   │
├─────────────────────────────────────────────────────────────┤
│  Host cluster (CentOS 7 / Rocky 8 / whatever)              │
│  GPU drivers · filesystem · job scheduler                   │
└─────────────────────────────────────────────────────────────┘
```

The container handles what needs root. Conda handles what needs flexibility.
Users get both without either.

## Quick start

```bash
# On Hoffman2 — copy scripts and run first-time setup
mkdir -p ~/bin
cp /u/project/kruglyak/PUBLIC_SHARED/containers/launch-devbox.sh ~/bin/
cp /u/project/kruglyak/PUBLIC_SHARED/containers/devbox-setup.sh ~/bin/
chmod +x ~/bin/launch-devbox.sh ~/bin/devbox-setup.sh

# First-time setup (creates conda env, ~15-20 min)
module load singularity
~/bin/launch-devbox.sh setup

# Get a compute node and start working
qrsh -l h_data=16G,h_rt=4:00:00 -pe shared 4
~/bin/launch-devbox.sh shell
```

## What you can do

```bash
launch-devbox.sh shell          # Interactive terminal
launch-devbox.sh code-server    # VS Code in your browser
launch-devbox.sh rstudio        # RStudio in your browser
launch-devbox.sh jupyter        # JupyterLab in your browser
launch-devbox.sh claude         # Claude Code AI assistant
launch-devbox.sh codex          # OpenAI Codex AI assistant
launch-devbox.sh gpu-job        # Request a GPU node
```

Install packages anytime — no container rebuild:

```bash
mamba install -n devbox -c conda-forge r-qs2       # conda
mamba install -n devbox -c bioconda bioconductor-deseq2  # bioconda
pip install some-package                            # PyPI
Rscript -e 'install.packages("qs2")'               # CRAN
npm install -g some-tool                            # npm
```

## Documentation

| Document | Audience | Contents |
|----------|----------|----------|
| **[README-user.md](README-user.md)** | Everyone | Setup guide, SSH tunneling, using each service, installing packages, tmux workflow, troubleshooting |
| **[README-build.md](README-build.md)** | Admins | Building the container, deploying to the cluster, common build issues, when to rebuild |
| **[README-architecture.md](README-architecture.md)** | Anyone curious | Why each piece exists, design decisions, tradeoffs, how to deploy on other clusters or cloud |

## Files

```
devbox-gpu.def       # Apptainer definition file (container recipe)
launch-devbox.sh     # Launch script (env setup, GPU detection, tunneling)
devbox-setup.sh      # First-time user setup (creates conda environment)
README.md            # This file
README-user.md       # User guide
README-build.md      # Build and deploy guide
README-architecture.md  # Architecture and design rationale
```

## Requirements

- A cluster with Apptainer or Singularity installed
- A separate Linux machine with root access to build the `.sif` (your
  workstation, a cloud VM, CI runner, etc.)
- Hoffman2-specific paths are hardcoded in `launch-devbox.sh` but
  easy to change for other clusters

## Adapting for other clusters

The architecture is portable. To use on a different cluster:

1. Rebuild the `.sif` (works anywhere — it's just Ubuntu + CUDA + libs)
2. Update `launch-devbox.sh`:
   - Change the default `SIF` path
   - Update bind mount paths for your cluster's filesystem layout
   - Change the `gpu-job` command to use your scheduler (SLURM, PBS, etc.)
3. Transfer and run `setup`

See [README-architecture.md](README-architecture.md) for details.

## License

MIT
