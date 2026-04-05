# DevBox Architecture — How and Why

## The problem

Hoffman2 runs CentOS 7, released in 2014. Its system libraries (glibc 2.17)
are too old to run modern development tools — Node.js 18+, the Claude Code
native binary, current R packages, and many Python wheels all require
glibc 2.25 or newer. You can't upgrade the OS because you're not root.
You can't compile from source because the system GCC and assembler are
also too old (AVX-512 instructions fail). And Hoffman2's module system
doesn't provide everything you need in compatible versions.

This is not unique to Hoffman2. Most HPC clusters run enterprise Linux
distributions (RHEL, CentOS, Rocky) that prioritize stability over
currency, and users don't have root. The same problem exists on many
academic and government clusters.

## The solution: two layers

DevBox uses a two-layer architecture to solve this:

    ┌─────────────────────────────────────────────────────────────┐
    │  Layer 2: User environment (conda)                         │
    │  ~/.devbox/conda/envs/devbox/                              │
    │                                                            │
    │  R 4.5, Python 3.12, Node.js 20, PyTorch, tidyverse,      │
    │  Bioconductor, Claude Code, Codex, Snakemake, Jupyter...   │
    │                                                            │
    │  ► Lives on your home directory                             │
    │  ► Each user has their own copy                             │
    │  ► Freely customizable (mamba install, pip install, etc.)   │
    │  ► No rebuild needed — just install what you want           │
    ├─────────────────────────────────────────────────────────────┤
    │  Layer 1: Base container (Apptainer .sif)                  │
    │  /u/project/kruglyak/PUBLIC_SHARED/containers/devbox-gpu.sif│
    │                                                            │
    │  Ubuntu 22.04, CUDA 12.4, system -dev libraries,           │
    │  build toolchain, Miniforge, code-server, RStudio Server   │
    │                                                            │
    │  ► Read-only, shared by all users                           │
    │  ► Only changes when system libs need updating              │
    │  ► Requires root to rebuild (done on a workstation)         │
    ├─────────────────────────────────────────────────────────────┤
    │  Host: Hoffman2 (CentOS 7, glibc 2.17)                    │
    │  Provides: filesystem, network, GPU drivers, job scheduler  │
    └─────────────────────────────────────────────────────────────┘

## Why Apptainer/Singularity?

Docker is the standard for containers, but it requires a daemon running
as root — a non-starter on shared HPC clusters. Apptainer (formerly
Singularity) was built specifically for HPC:

- **Runs as your user.** No root, no daemon, no privilege escalation.
  You are the same user inside and outside the container. Your files
  have the same permissions. This is critical for shared clusters.

- **Accesses host filesystems.** Your home directory, scratch, project
  space, and GPU drivers are all visible inside the container via bind
  mounts. You don't need to copy data into the container.

- **GPU passthrough with --nv.** The `--nv` flag bind-mounts the host's
  NVIDIA driver into the container. The container provides CUDA toolkit
  and libraries; the host provides the actual GPU driver. They just need
  to be version-compatible.

- **Single-file images.** A `.sif` file is one portable, read-only file.
  Copy it anywhere, run it. No registry, no layers, no docker-compose.

- **Compatible with Docker images.** You can bootstrap from any Docker
  image (we use `nvidia/cuda:12.4.1-runtime-ubuntu22.04`).

## Why conda for packages (instead of baking them into the container)?

Early versions of DevBox baked R, Python, and all packages into the `.sif`.
This caused several problems:

- **Slow iteration.** Adding one missing library meant rebuilding the
  entire container on a workstation (30-60 min), transferring 10+ GB
  to Hoffman2, and testing. Each solver conflict or build error restarted
  this cycle.

- **One-size-fits-none.** Different users need different packages.
  Baking a fixed set into the container means either a bloated image
  with everything, or users unable to add what they need.

- **Version conflicts.** R and Python packages installed inside the
  container used the container's GCC (from conda-forge), which couldn't
  find system `-dev` libraries installed via `apt-get`. The two
  toolchains clashed.

The solution: the container provides only the system libraries and build
toolchain. All user-facing software lives in a conda environment on the
host filesystem:

- **Users install packages themselves.** `mamba install`, `pip install`,
  `install.packages()` — no container rebuild, no admin needed.

- **Each user has their own environment.** Your packages don't affect
  anyone else. You can break and rebuild your env freely.

- **Conda provides consistent toolchains.** When conda installs R or
  Python, it also provides a matching GCC, libraries, and headers.
  Source compilation uses conda's toolchain against conda's libraries —
  no mismatches.

- **MKL integration.** Conda can pin Intel MKL as the BLAS/LAPACK
  backend for both R and Python, giving faster linear algebra without
  any manual configuration.

## Why the environment isolation?

Hoffman2 users often have R and Python packages installed in their home
directory from non-container use (via `module load R`, `pip install --user`,
etc.). Without isolation, the container's R/Python would find and load
these packages, causing version conflicts and crashes.

DevBox isolates everything under `~/.devbox/`:

    ~/.devbox/
    ├── conda/envs/devbox/   # R, Python, Node.js, and conda packages
    ├── R/library/           # R packages from install.packages()
    ├── pip/                 # pip packages (PYTHONUSERBASE)
    ├── npm-global/          # npm global packages (Claude, Codex)
    ├── bashrc               # Shell init (auto-generated)
    └── env                  # API keys

Key environment variables enforce this:

- `R_LIBS_USER=~/.devbox/R/library` — R installs here, not ~/R/
- `R_ENVIRON_USER=~/.devbox/R/Renviron` — ignores any ~/.Renviron
- `PYTHONNOUSERSITE=1` — Python ignores ~/.local/lib/python3.x/
- `PYTHONUSERBASE=~/.devbox/pip` — pip --user goes here
- `NPM_CONFIG_PREFIX=~/.devbox/npm-global` — npm globals go here
- `CONDA_ENVS_PATH=~/.devbox/conda/envs` — conda envs stored here

These are passed into the container via `SINGULARITYENV_` prefixed
variables, which Apptainer injects into the container's environment
even for `singularity shell` (which starts a fresh login shell).

## How the services work

### code-server (VS Code in browser)

code-server is a build of VS Code that runs as an HTTP server. It's
installed inside the container at `/opt/code-server`. When you launch it,
it binds to a port on the compute node, and you access it via SSH tunnel
from your laptop.

The launch script configures code-server's `settings.json` to:
- Use the devbox conda env for terminal shells
- Point the R and Python extensions to the conda env's binaries
- Exclude large directories from file watching (to avoid inotify limits)
- Use polling-based file watching (HPC clusters have low inotify limits)

### RStudio Server

RStudio Server is installed via its official `.deb` package inside the
container. Running it in Apptainer requires special handling:

- **Authentication:** Standard PAM auth doesn't work inside Apptainer
  (no root, no system users). A custom `rstudio_auth` script checks
  passwords against the `RSTUDIO_PASSWORD` environment variable.

- **Writable directories:** RStudio needs to write to `/run`,
  `/var/lib/rstudio-server`, and `/tmp`. These are bind-mounted from
  `~/.devbox/rstudio/` so each user has their own writable state.

- **R discovery:** The `--rsession-which-r` flag and an `rsession.sh`
  wrapper script ensure RStudio uses the conda env's R, not any system R.

### SSH tunneling

Compute nodes are not directly accessible from outside the cluster.
To reach a service running on compute node `n7234`, you tunnel through
the login node:

    laptop:8080 → login-node → n7234:8080

The SSH command `ssh -L 8080:n7234:8080 hoffman2` creates this tunnel.
Services bind to `0.0.0.0` (not `127.0.0.1`) because the tunnel connects
to the compute node's IP, not its localhost.

### tmux for persistence

SSH connections drop. If you're running code-server in your SSH session
and the connection dies, code-server dies too. tmux on the compute node
keeps processes running after disconnection. You reconnect and reattach.

tmux runs on the compute node, outside the container. The container
processes are children of tmux, so they survive SSH disconnects.

## Deploying elsewhere

### Another HPC cluster (SLURM, PBS, SGE)

The architecture is portable. What changes:

| Component          | Hoffman2 (SGE)              | Other cluster              |
|--------------------|-----------------------------|----------------------------|
| Job scheduler      | `qrsh`, `qsub`             | `srun`, `sbatch` (SLURM)  |
| GPU request        | `-l gpu,V100`               | `--gres=gpu:v100:1`       |
| Project paths      | `/u/project`, `/u/scratch`  | Cluster-specific           |
| Container runtime  | `singularity` module        | May be `apptainer`         |
| SIF location       | `/u/project/kruglyak/...`   | Shared project dir         |

To adapt: update the bind mounts in `launch-devbox.sh`, change the
`gpu-job` command to use the local scheduler, and update the default
SIF path.

The `.sif` file itself is portable — copy it to any Linux machine with
Apptainer/Singularity and it runs. The conda environment is also portable
across machines with the same architecture (x86_64).

### Cloud VMs (AWS, GCP, Azure)

On a cloud VM you typically have root, so you could skip the container
and install everything directly. But the container is still useful for:

- **Reproducibility.** Same environment everywhere.
- **Multi-user.** Multiple users on one VM, each with isolated envs.
- **Quick setup.** Copy the `.sif`, run setup, done.

The main difference: cloud VMs have root access, so the container is
optional rather than required.

### Docker / Kubernetes

If you need a Docker image instead of a `.sif` (e.g., for Kubernetes or
cloud container services), build a Docker image from the same def file
concept:

    # Build as Docker first
    docker build -t devbox-gpu .

    # Convert to SIF if also needed on HPC
    singularity build devbox-gpu.sif docker-daemon://devbox-gpu:latest

The Dockerfile would mirror the def file's `%post` section.

## Design decisions and tradeoffs

### Why not just use conda on the host (no container)?

Conda can install its own GCC and most libraries, but:

- R packages that use `configure` scripts often look for system libraries
  in `/usr/lib` and `/usr/include`. On CentOS 7, these are ancient or
  missing. The container provides a modern Ubuntu with current `-dev`
  packages.

- Some tools (code-server, RStudio Server) need system-level installation
  (systemd, PAM, etc.) that conda can't provide.

- The container guarantees a consistent base regardless of what's
  installed on the host.

### Why not bake everything into the container?

As discussed above, this was the original approach. It works but the
feedback loop is painfully slow. The thin-base approach means:

- Container rebuilds are rare and fast (~10 min, ~3 GB)
- Users are self-service for packages
- Different users can have different R/Python versions if needed

### Why do Claude Code and Codex need the container?

Even with conda providing Node.js, `npm install -g @anthropic-ai/claude-code`
and `npm install -g @openai/codex` fail on the bare Hoffman2 host. These
packages ship prebuilt native binaries (via `node-gyp` or bundled `.node`
addons) that are compiled against glibc 2.28+ and link to modern system
libraries like `libstdc++` and `libssl`. Conda's Node.js itself runs fine
because conda ships its own glibc, but npm postinstall scripts download or
compile native code that dynamically links against the *system* glibc
(`/lib64/libc.so.6`), not conda's. On CentOS 7 (glibc 2.17), this produces
errors like:

    /lib64/libc.so.6: version `GLIBC_2.25' not found
    /lib64/libc.so.6: version `GLIBC_2.28' not found

There's no way to fix this without replacing the system's glibc, which
requires root. Running the install inside the Apptainer container sidesteps
the problem entirely — the container provides Ubuntu 22.04 with glibc 2.35,
so the native binaries find everything they need. The installed binaries
land in `~/.devbox/npm-global/bin/` (on the host filesystem via bind mount),
and at runtime they work because `launch-devbox.sh` always runs them inside
the container where the modern glibc is available.

### Why MKL instead of OpenBLAS?

MKL is generally faster for the linear algebra workloads common in
statistics and genomics (matrix operations, eigendecompositions, SVD).
Conda makes it easy to swap: `libblas=*=*mkl` vs `libblas=*=*openblas`.

### Why Python 3.12 (not 3.13 or 3.14)?

Bioinformatics packages on bioconda (pysam, pybedtools) lag behind
Python releases. As of this writing, pybedtools only has builds up to
Python 3.12. The setup script pins Python to ensure the solver can
find compatible versions of everything.

### Why R 4.5 (not 4.4)?

Current CRAN packages (particularly rlang) require R 4.5 features
like `R_mkClosure`. Using R 4.4 causes runtime crashes when loading
packages compiled against the latest rlang.

## Summary

    ┌──────────────────────────────────────────────────────────┐
    │                     You interact with                    │
    │                                                          │
    │    launch-devbox.sh  →  manages everything below         │
    │                                                          │
    ├──────────────────────────────────────────────────────────┤
    │                                                          │
    │    Browser tools          Terminal tools                  │
    │    ┌────────────┐        ┌────────────┐                  │
    │    │ code-server│        │ claude     │                  │
    │    │ RStudio    │        │ codex      │                  │
    │    │ JupyterLab │        │ R / python │                  │
    │    └────────────┘        │ snakemake  │                  │
    │         ↑                └────────────┘                  │
    │    SSH tunnel                  ↑                          │
    │    from laptop           conda env on $HOME              │
    │                                                          │
    ├──────────────────────────────────────────────────────────┤
    │                                                          │
    │    Apptainer container (.sif)                             │
    │    Ubuntu 22.04 + CUDA + system libs + build toolchain   │
    │                                                          │
    ├──────────────────────────────────────────────────────────┤
    │                                                          │
    │    Host cluster (CentOS 7 / Rocky 8 / whatever)          │
    │    GPU drivers, filesystem, job scheduler                 │
    │                                                          │
    └──────────────────────────────────────────────────────────┘
