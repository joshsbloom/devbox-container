# DevBox

A portable, GPU-enabled development environment for HPC clusters.

DevBox packages VS Code, RStudio, JupyterLab, Claude Code, Codex, R, Python,
and a full bioinformatics stack into a containerized setup that runs on
clusters with outdated operating systems — no root access required.

## How it works

DevBox uses two layers so you get a modern environment without needing admin
privileges:

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

## Quick start (Hoffman2)

**If you're new to Hoffman2**, start with the step-by-step
[User Guide](README-user.md) — it explains each command as you go.

If you're comfortable with HPC clusters, here's the short version:

```bash
# 1. SSH to Hoffman2
ssh <user>@hoffman2.idre.ucla.edu

# 2. Get the scripts (one-time)
git clone https://github.com/joshsbloom/devbox-container.git ~/Local/devbox-container
chmod +x ~/Local/devbox-container/launch-devbox.sh ~/Local/devbox-container/devbox-setup.sh
mkdir -p ~/Local/bin
ln -sf ~/Local/devbox-container/launch-devbox.sh ~/Local/bin/launch-devbox.sh
ln -sf ~/Local/devbox-container/devbox-setup.sh ~/Local/bin/devbox-setup.sh

# 3. Add to your PATH so you can run "launch-devbox.sh" from anywhere (one-time)
echo 'export PATH="$HOME/Local/bin:$PATH"' >> ~/.bashrc
echo 'module load singularity' >> ~/.bashrc
source ~/.bashrc

# 4. Get a compute node (setup needs resources — don't run on the login node)
qrsh -l h_data=8G,h_rt=8:00:00 -pe shared 4

# 5. First-time setup (creates conda env with base packages)
launch-devbox.sh setup

# 6. Optionally add domain-specific packages (additive — install anytime)
launch-devbox.sh setup --with bioinfo    # pysam, scanpy, Bioconductor
launch-devbox.sh setup --with ml         # PyTorch with CUDA
launch-devbox.sh setup --with r-extra    # tidyverse, lme4, brms
launch-devbox.sh setup --with all        # everything

# 7. Start working
launch-devbox.sh shell
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

Create project-specific environments:

```bash
mamba create -n myproject python=3.11 pandas
DEVBOX_ENV=myproject launch-devbox.sh shell
```

## Documentation

| Document | Audience | Contents |
|----------|----------|----------|
| **[README-user.md](README-user.md)** | Everyone | Step-by-step setup, SSH tunneling, using each service, installing packages, troubleshooting |
| **[README-hoffman2.md](README-hoffman2.md)** | Everyone | Hoffman2 filesystem layout, storage quotas, best practices, job scheduler tips |
| **[README-build.md](README-build.md)** | Admins | Building the container, deploying to the cluster, common build issues |
| **[README-architecture.md](README-architecture.md)** | Anyone curious | Why each piece exists, design decisions, deploying on other clusters |

## Files

```
devbox-gpu.def       # Apptainer definition file (container recipe)
launch-devbox.sh     # Launch script (env setup, GPU detection, tunneling)
devbox-setup.sh      # First-time user setup (creates conda environment)
README.md            # This file
README-user.md       # User guide
README-hoffman2.md   # Hoffman2 best practices and filesystem guide
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
