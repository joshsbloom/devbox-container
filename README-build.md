# Building the DevBox Apptainer Container

## Overview

The DevBox container provides a minimal, GPU-enabled development environment
for the Hoffman2 cluster. It packages only what requires root privileges to
install — system libraries, a build toolchain, conda/mamba, code-server, and
RStudio Server. All user-facing software (R, Python, Node.js, packages) is
installed via conda into user home directories at runtime.

## Prerequisites

You need a Linux machine with root access (or fakeroot) to build the container.
Your personal workstation works fine for this. Hoffman2 does not allow
container builds.

Install Apptainer (or Singularity):

    # Ubuntu/Debian
    sudo apt install apptainer

    # Or from source: https://apptainer.org/docs/admin/main/installation.html

## What's in the container

**System packages:**
- Ubuntu 22.04 base with NVIDIA CUDA 12.4 runtime
- C/C++/Fortran build toolchain (gcc, g++, gfortran, cmake, pkg-config, autoconf, etc.)
- Development libraries for compiling R and Python packages from source:
  libcurl, libssl, libxml2, libhdf5, libcairo2, libgdal, libgeos, libboost,
  libprotobuf, libzmq, libopenblas, libnlopt, libfftw3, libmagick++,
  libpoppler-cpp, libtesseract, and many more

**Tools:**
- Miniforge (conda + mamba) at `/opt/miniforge3`
- code-server 4.113.0 (VS Code in the browser) at `/opt/code-server`
- RStudio Server 2026.01.2 at `/usr/lib/rstudio-server`

**What's NOT in the container:**
- R, Python, Node.js, and all packages — these are installed per-user via
  conda during first-time setup, so they can be customized without rebuilding

## What the setup script installs (per user)

The `devbox-setup.sh` script creates a conda environment. The base setup
includes:
- Python 3.12, R 4.5, Node.js 20
- Intel MKL as the BLAS/LAPACK backend (for R and numpy)
- Core data science: numpy, scipy, pandas, scikit-learn, matplotlib, etc.
- R: irkernel, languageserver, httpgd
- CLI: Claude Code, OpenAI Codex
- JupyterLab with R and Python kernels

Optional profiles add domain-specific packages:
- `--with bioinfo`: pysam, pybedtools, scanpy, snakemake, Bioconductor
- `--with ml`: PyTorch with CUDA 12.4 support
- `--with r-extra`: tidyverse, data.table, lme4, brms, Bioconductor, etc.
- `--with all`: everything above

Profiles can be installed during initial setup or added later.

## Building

    sudo singularity build devbox-gpu.sif devbox-gpu.def

    # Or with Apptainer:
    apptainer build --fakeroot devbox-gpu.sif devbox-gpu.def

Build time is approximately 10-20 minutes. The resulting `.sif` file will be
roughly 3-5 GB.

## Common build issues

**Inline comments in apt-get:**
The `%post` section runs under `/bin/sh`. Do NOT put `# comments` on
continuation lines inside `apt-get install` — they break the command.
Keep comments above the `apt-get` call.

**Package conflicts:**
If `apt-get` fails with dependency conflicts (e.g., `libmariadb-dev` vs
`libmysqlclient-dev`), check which package the CUDA base image already
provides and use that one instead.

**Network errors:**
The build needs to download packages from the internet. If it fails on
`curl` or `apt-get` commands, check your network connection and any
proxy settings.

## Deploying to Hoffman2

### Container image

The `.sif` file must be copied to the shared project directory:

    # Transfer the .sif file (3-5 GB, may take a while)
    scp devbox-gpu.sif <user>@hoffman2.idre.ucla.edu:/u/project/kruglyak/PUBLIC_SHARED/containers/

    # Set permissions so all group members can read it
    ssh <user>@hoffman2.idre.ucla.edu
    chmod 755 /u/project/kruglyak/PUBLIC_SHARED/containers/devbox-gpu.sif

### Scripts

Users get the scripts by cloning the repository themselves (see the
[User Guide](README-user.md)). This means script updates are distributed
via `git pull` — no need for admins to copy files around. Each user runs:

    git clone https://github.com/joshsbloom/devbox-container.git ~/Local/devbox-container

To pick up script updates later:

    cd ~/Local/devbox-container && git pull

## Updating the container

Only rebuild the `.sif` when you need to change something that requires root:
- Adding or updating system `-dev` libraries
- Updating code-server or RStudio Server versions
- Changing the CUDA version
- Updating the base OS

For everything else (R packages, Python packages, conda environments),
users update their own environments without any container rebuild.

## Files

| File               | Purpose                                              |
|--------------------|------------------------------------------------------|
| `devbox-gpu.def`   | Apptainer definition file (the build recipe)         |
| `devbox-gpu.sif`   | Built container image (read-only, shared by all)     |
| `launch-devbox.sh` | Launch script (handles env setup, GPU, tunneling)    |
| `devbox-setup.sh`  | First-time user setup (creates conda environment)    |
| `README-build.md`  | This file — build and deploy instructions            |
| `README-user.md`   | User-facing guide for Hoffman2 usage                 |
