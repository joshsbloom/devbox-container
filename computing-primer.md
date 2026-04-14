# A Brief Primer on Kernels, OSes, Containers, and Conda

## What is a kernel?

The **kernel** is the core program of an operating system. It runs in a privileged CPU mode and is the only software allowed to talk directly to hardware. Its jobs:

- **Process scheduling** — decides which program runs on which CPU core and for how long.
- **Memory management** — hands out RAM to processes, enforces isolation so one program can't read another's memory.
- **Device I/O** — drivers for disks, GPUs, network cards, USB, etc.
- **System calls** — the API (`read`, `write`, `open`, `mmap`, `fork`, …) that user programs use to ask the kernel to do privileged things.
- **Filesystems & networking stacks** — VFS, TCP/IP, etc.

On Linux, "the kernel" is literally the file `/boot/vmlinuz-*`. Everything else (shell, compiler, browser, systemd) is just user-space software running on top of it.

## What is a modern OS?

An **operating system** is the kernel *plus* the surrounding user-space that makes a computer usable:

- **Kernel** (see above).
- **C library** (`glibc`, `musl`) — the thin layer every other program links against to make syscalls.
- **Init system** (`systemd`, `launchd`) — starts and supervises background services.
- **Shell & core utilities** (`bash`, `zsh`, `ls`, `grep`, `cp`).
- **Package manager** (`apt`, `dnf`, `pacman`, `brew`) — installs and updates software.
- **Window system / desktop** (Wayland/X11 + GNOME/KDE on Linux; Quartz + AppKit on macOS).
- **Driver model, security model, networking config, user accounts**, etc.

Modern OSes (Linux, macOS, Windows) share the same basic shape: preemptive multitasking, virtual memory, protected mode, multi-user, networked by default.

## What does Apptainer abstract?

**Apptainer** (formerly Singularity) is a **container runtime** designed for HPC clusters. A container bundles an entire user-space (a specific Ubuntu, specific libraries, specific Python, specific CUDA) into a single file (`.sif`) that runs on top of the host's kernel.

What it abstracts away:

- **The host OS distribution.** Your `.sif` can be Ubuntu 22.04 even if the cluster runs CentOS 7 with a 10-year-old glibc.
- **System library versions.** No more "GLIBC_2.34 not found" — you ship your own.
- **Install permissions.** You don't need root on the cluster; the container is a read-only file you execute.
- **Reproducibility.** The same `.sif` behaves identically on your laptop and on 500 compute nodes.

Unlike Docker, Apptainer runs as your user (no daemon, no root), mounts `$HOME` by default, and plays nicely with GPUs via `--nv` and with shared filesystems and schedulers (SLURM, SGE).

It does **not** abstract the kernel — GPU drivers, filesystems, and syscalls still come from the host.

## What does Docker abstract?

**Docker** is the dominant general-purpose **container platform**. Like Apptainer, it bundles an entire user-space (OS libraries, language runtimes, app code) into an image that runs on top of the host kernel. What it abstracts:

- **The host OS distribution.** An image built on Ubuntu runs on RHEL, Alpine, macOS, or Windows hosts (via a Linux VM on the latter two).
- **Dependency hell.** "Works on my machine" → ship the machine. No more mismatched library versions between dev, CI, and prod.
- **Install & teardown.** `docker run` pulls and starts; `docker rm` wipes it. No package-manager residue on the host.
- **Networking & ports.** Each container gets its own network namespace; you map ports explicitly.
- **Layered filesystems.** Images are built from stacked, cached layers (`Dockerfile`), so rebuilds only redo what changed.
- **Orchestration hooks.** Images are the unit of deployment for Kubernetes, ECS, Compose, etc.

Key differences from Apptainer: Docker runs via a **root-owned daemon**, isolates `$HOME` by default, and is built for cloud/web services rather than HPC. Apptainer was designed because running a root daemon on a shared cluster is a non-starter.

## What is conda?

**Conda** is a cross-platform **package and environment manager**. Unlike `pip` (Python-only) or `apt` (system-wide, needs root), conda:

- Installs **binary** packages for Python, R, C/C++ libraries, CUDA toolkits, compilers, CLI tools — all into a user-owned directory.
- Creates isolated **environments** so project A can use Python 3.10 + PyTorch 2.1 while project B uses Python 3.12 + TensorFlow.
- Does not require root.

**Miniforge** is the recommended minimal installer: it's conda pre-configured to use the community **conda-forge** channel (and works out of the box on Apple Silicon). `mamba` is a faster drop-in replacement for `conda` bundled with Miniforge — it's written in C++ and resolves dependencies in parallel, so environment creation that takes minutes with `conda` often takes seconds with `mamba`.

### Using mamba

`mamba` takes the same subcommands and flags as `conda`, so you can almost always just swap the command name:

```bash
mamba create -n myenv python=3.12 numpy pandas pytorch
mamba activate myenv        # activate/deactivate still work the same
mamba install -c conda-forge scikit-learn r-base
mamba update --all
mamba env create -f environment.yml
mamba env remove -n myenv
mamba search pytorch        # much faster than 'conda search'
```

Rule of thumb: use `mamba` for anything that touches the solver (`create`, `install`, `update`, `remove`, `env create`). Use `conda` for config and activation (`conda config`, `conda activate`) — both work, but `conda activate` is the canonical one.

### Setup on macOS (Apple Silicon, arm64)

```bash
# Download Miniforge for arm64
curl -L -O https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-MacOSX-arm64.sh
bash Miniforge3-MacOSX-arm64.sh -b -p "$HOME/miniforge3"

# Initialize your shell (zsh is default on macOS)
"$HOME/miniforge3/bin/conda" init zsh
exec zsh

# Verify
conda info
conda config --show channels   # should show conda-forge
```

### Setup on Linux (x86-64)

```bash
# Download Miniforge for x86_64
curl -L -O https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh
bash Miniforge3-Linux-x86_64.sh -b -p "$HOME/miniforge3"

# Initialize (bash shown; use 'zsh' if that's your shell)
"$HOME/miniforge3/bin/conda" init bash
exec bash

# Verify
conda info
```

### Basic usage

```bash
conda create -n myenv python=3.12 numpy pandas
conda activate myenv
conda install -c conda-forge pytorch
conda deactivate
conda env list
conda env remove -n myenv
```

## When conda gets borked — fixing and removing

Symptoms: solver hangs forever, `CondaHTTPError`, `libmamba` crashes, base env refuses to activate, mystery `PATH` pollution from an old Anaconda install.

### Fix attempts (least to most nuclear)

- **Reset channels** if a bad channel was added:
  ```bash
  conda config --remove-key channels
  conda config --add channels conda-forge
  ```
- **Clean caches** (stale package tarballs, index cache):
  ```bash
  conda clean --all
  ```
- **Update the solver / conda itself**:
  ```bash
  conda update -n base -c conda-forge conda mamba
  ```
- **Rebuild a broken env from scratch** — faster and more reliable than "repairing":
  ```bash
  conda env export -n myenv > myenv.yml   # if still readable
  conda env remove -n myenv
  conda env create -f myenv.yml
  ```

### Full uninstall (nuclear option)

Official docs: <https://docs.anaconda.com/anaconda/install/uninstall/>

```bash
# 1. Remove the install directory
rm -rf ~/miniforge3 ~/miniconda3 ~/anaconda3

# 2. Remove per-user state
rm -rf ~/.conda ~/.condarc ~/.continuum ~/.anaconda

# 3. Strip the 'conda initialize' block from your shell rc files
#    (edit manually, or use `conda init --reverse --all` *before* deleting the install dir)
#   ~/.bashrc  ~/.zshrc  ~/.bash_profile  ~/.profile
```

After that, open a new shell — `which conda` should return nothing — and reinstall Miniforge cleanly using the steps above.

### Useful reference links

- Miniforge (recommended installer): <https://github.com/conda-forge/miniforge>
- Conda user guide: <https://docs.conda.io/projects/conda/en/latest/user-guide/>
- Managing environments: <https://docs.conda.io/projects/conda/en/latest/user-guide/tasks/manage-environments.html>
- Troubleshooting: <https://docs.conda.io/projects/conda/en/latest/user-guide/troubleshooting.html>
- Uninstalling Anaconda/Miniconda: <https://docs.anaconda.com/anaconda/install/uninstall/>
- `conda clean` reference: <https://docs.conda.io/projects/conda/en/latest/commands/clean.html>
- conda-forge FAQ (channel priority, mixing with defaults): <https://conda-forge.org/docs/user/tipsandtricks/>
