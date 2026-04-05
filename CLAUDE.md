# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

DevBox: a portable, GPU-enabled development environment for HPC clusters (primarily UCLA's Hoffman2). It packages VS Code, RStudio, JupyterLab, Claude Code, Codex, R, Python, and a bioinformatics stack into an Apptainer container that runs on clusters with outdated OS — no root access required.

## Architecture

Two-layer design:
- **Layer 1 (container):** Read-only `.sif` file with Ubuntu 22.04, CUDA 12.4, system `-dev` libraries, build toolchain, Miniforge, code-server, and RStudio Server. Shared by all users, requires root to rebuild.
- **Layer 2 (conda env on `$HOME`):** R 4.5, Python 3.12, Node.js 20, PyTorch, all packages. Per-user, freely customizable, no rebuild needed.

Everything user-facing lives under `~/.devbox/` to isolate from host installs. Environment variables (`R_LIBS_USER`, `PYTHONNOUSERSITE`, `CONDA_ENVS_PATH`, etc.) enforce this isolation and are passed into the container via `SINGULARITYENV_`/`APPTAINERENV_` prefixed exports.

## Key files

- `devbox-gpu.def` — Apptainer definition file (container build recipe). Bootstraps from `nvidia/cuda` Docker image, installs system libs, Miniforge, code-server, RStudio Server.
- `launch-devbox.sh` — Entry point for all operations. Handles GPU detection (`--nv`), bind mounts, environment isolation, per-user `/tmp`, and launches services (shell, code-server, rstudio, jupyter, claude, codex, gpu-job).
- `devbox-setup.sh` — First-time setup run inside the container. Creates the conda environment with all packages, installs Claude Code and Codex via npm, registers R kernel for Jupyter, verifies MKL linkage.

## Build commands

```bash
# Build the container (requires root/fakeroot, done on a workstation, NOT on the cluster)
sudo singularity build devbox-gpu.sif devbox-gpu.def

# Deploy to Hoffman2
scp devbox-gpu.sif <user>@hoffman2.idre.ucla.edu:/u/project/kruglyak/PUBLIC_SHARED/containers/
```

## Important design constraints

- **No inline comments in apt-get continuation lines** in the def file `%post` section — they break the command under `/bin/sh`.
- **inotify limits:** Hoffman2 has ~8192 inotify limit that can't be changed. code-server uses polling-based file watching (`CHOKIDAR_USEPOLLING=1`) and excludes large directories to avoid ptyHost crashes.
- **Services bind to `0.0.0.0`** (not localhost) because SSH tunnels connect to the compute node's IP.
- **Python pinned to 3.12** because bioconda packages (pysam, pybedtools) lack builds for newer versions.
- **R pinned to 4.5** because current rlang requires `R_mkClosure` (crashes on R 4.4).
- **MKL is the BLAS/LAPACK backend** (`libblas=*=*mkl`) for both R and Python — faster for stats/genomics workloads.
- Only rebuild the `.sif` for system-level changes (system libs, code-server/RStudio versions, CUDA, base OS). Package changes are user-managed via conda.
