#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
# launch-devbox.sh — Launch the devbox Apptainer container on Hoffman2
#
# Intended workflow:
#   1. SSH to Hoffman2 login node
#   2. qrsh to get an interactive compute node
#   3. Run this script on the compute node
#
# Usage:
#   ./launch-devbox.sh setup [--with bioinfo,ml]  # first-time setup
#   ./launch-devbox.sh shell          # interactive shell
#   ./launch-devbox.sh code-server    # VS Code in browser
#   ./launch-devbox.sh rstudio        # RStudio Server in browser
#   ./launch-devbox.sh jupyter        # JupyterLab in browser
#   ./launch-devbox.sh claude         # Claude Code CLI
#   ./launch-devbox.sh codex          # Codex CLI
#   ./launch-devbox.sh gpu-job        # request GPU node then launch shell
#   ./launch-devbox.sh exec <cmd>     # arbitrary command
#
# Options:
#   --no-gpu / --cpu                  # disable GPU passthrough
#   --verbose / -v                    # print singularity commands
#   DEVBOX_ENV=myenv                  # use a different conda environment
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Cluster configuration ───────────────────────────────────────────────
# Change these when adapting for a different cluster
SIF="${DEVBOX_SIF:-/u/project/kruglyak/PUBLIC_SHARED/containers/devbox-gpu.sif}"
LOGIN_HOST="${DEVBOX_LOGIN_HOST:-hoffman2.idre.ucla.edu}"
GPU_JOB_CMD="${DEVBOX_GPU_JOB_CMD:-qrsh}"    # qrsh (SGE), srun (SLURM)
EXTRA_BIND_PATHS="${DEVBOX_EXTRA_BINDS:-}"    # colon-separated additional bind paths

DEVBOX_HOME="$HOME/.devbox"
ENV_NAME="${DEVBOX_ENV:-devbox}"
ENV_PATH="$DEVBOX_HOME/conda/envs/$ENV_NAME"
COMPUTE_NODE=$(hostname)

CODE_SERVER_PORT="${CODE_SERVER_PORT:-8080}"
RSTUDIO_PORT="${RSTUDIO_PORT:-8787}"
JUPYTER_PORT="${JUPYTER_PORT:-8888}"

# Source API keys
[[ -f "$DEVBOX_HOME/env" ]] && source "$DEVBOX_HOME/env"

# ── Helper: print SSH tunnel info ────────────────────────────────────────
print_tunnel() {
    local port="$1"
    echo ""
    echo "  Compute node: ${COMPUTE_NODE}"
    echo "  SSH tunnel:   ssh -L ${port}:${COMPUTE_NODE}:${port} ${USER}@${LOGIN_HOST}"
    echo "  Open:         http://localhost:${port}"
    echo ""
}

# ── Parse flags ──────────────────────────────────────────────────────────
FORCE_NO_GPU=false
VERBOSE=false
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --no-gpu|--cpu) FORCE_NO_GPU=true ;;
        --verbose|-v) VERBOSE=true ;;
        *) ARGS+=("$arg") ;;
    esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

# ── GPU detection ────────────────────────────────────────────────────────
GPU_FLAGS=()
if [[ "$FORCE_NO_GPU" == false ]] && [[ -e /dev/nvidia0 || -e /dev/nvidiactl ]]; then
    GPU_FLAGS=("--nv")
    echo "[devbox] GPU detected — enabling --nv"
else
    echo "[devbox] CPU-only mode"
fi

# ── Bind mounts ──────────────────────────────────────────────────────────
BINDS=("--bind" "$HOME:$HOME")
[[ -d "/u/scratch" ]] && BINDS+=("--bind" "/u/scratch:/u/scratch")
[[ -d "/u/project" ]] && BINDS+=("--bind" "/u/project:/u/project")

# Extra bind paths for other clusters
if [[ -n "$EXTRA_BIND_PATHS" ]]; then
    IFS=':' read -ra EXTRA_BINDS <<< "$EXTRA_BIND_PATHS"
    for bp in "${EXTRA_BINDS[@]}"; do
        [[ -d "$bp" ]] && BINDS+=("--bind" "$bp:$bp")
    done
fi

# Per-user /tmp to avoid collisions on shared compute nodes
USER_TMP="$DEVBOX_HOME/tmp/${COMPUTE_NODE}-$$"
mkdir -p "$USER_TMP"
BINDS+=("--bind" "$USER_TMP:/tmp")
trap 'rm -rf "$USER_TMP" 2>/dev/null || true' EXIT

# ── Environment isolation ────────────────────────────────────────────────
# Use APPTAINERENV_ / SINGULARITYENV_ prefixes so variables are passed
# into the container even for `singularity shell` (which starts a fresh shell)
set_container_env() {
    local name="$1" value="$2"
    export "SINGULARITYENV_${name}=${value}"
    export "APPTAINERENV_${name}=${value}"
    export "${name}=${value}"
}

# All package paths go under ~/.devbox/ to avoid clashing with host installs
set_container_env CONDA_ENVS_PATH "$DEVBOX_HOME/conda/envs"
set_container_env CONDA_PKGS_DIRS "$DEVBOX_HOME/conda/pkgs"
set_container_env R_LIBS_USER "$DEVBOX_HOME/R/library"
set_container_env R_LIBS_SITE ""
set_container_env R_ENVIRON_USER "$DEVBOX_HOME/R/Renviron"
set_container_env RENV_PATHS_CACHE "$DEVBOX_HOME/renv-cache"
set_container_env PYTHONUSERBASE "$DEVBOX_HOME/pip"
set_container_env PYTHONNOUSERSITE 1
set_container_env NPM_CONFIG_PREFIX "$DEVBOX_HOME/npm-global"
set_container_env JUPYTER_DATA_DIR "$DEVBOX_HOME/jupyter"
set_container_env JUPYTER_RUNTIME_DIR "$DEVBOX_HOME/jupyter/runtime"

# Force polling-based file watching instead of inotify
# Hoffman2 has low inotify limits (~8192) that can't be changed without root.
# VS Code/code-server crashes (ptyHost SIGINT) when these are exhausted.
set_container_env CHOKIDAR_USEPOLLING 1
set_container_env TSC_WATCHFILE UseFsEventsWithFallbackDynamicPolling

# Activate the conda env by prepending to the container's default PATH
CONTAINER_BASE_PATH="/opt/miniforge3/bin:/opt/code-server/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
if [[ -d "$ENV_PATH/bin" ]]; then
    DEVBOX_PATH="$ENV_PATH/bin:$DEVBOX_HOME/npm-global/bin"
    FULL_PATH="${DEVBOX_PATH}:${CONTAINER_BASE_PATH}"
    export SINGULARITYENV_PATH="$FULL_PATH"
    export APPTAINERENV_PATH="$FULL_PATH"
    set_container_env CONDA_DEFAULT_ENV "$ENV_NAME"
    set_container_env CONDA_PREFIX "$ENV_PATH"
else
    FULL_PATH="$CONTAINER_BASE_PATH"
fi

# Ensure every bash shell inside the container (including RStudio/code-server
# terminals) sources the devbox init file. BASH_ENV is read by non-interactive
# shells; the bashrc also sources itself for interactive ones.
set_container_env BASH_ENV "$DEVBOX_HOME/bashrc"

[[ "$ENV_NAME" != "devbox" ]] && echo "[devbox] Using conda environment: $ENV_NAME"

# ── Write shell init file for code-server / RStudio terminals ────────────
# code-server and RStudio spawn their own terminal shells that don't
# inherit SINGULARITYENV_ variables. This init file ensures every
# new terminal gets the devbox environment.
DEVBOX_BASHRC="$DEVBOX_HOME/bashrc"
cat > "$DEVBOX_BASHRC" <<RCEOF
# DevBox shell init — auto-generated by launch-devbox.sh
# Guard against double-sourcing (profile.d + bash.bashrc + BASH_ENV)
[[ -n "\${DEVBOX_ENV_LOADED:-}" ]] && return
export DEVBOX_ENV_LOADED=1

[[ -f \$HOME/.bashrc_hoffman2 ]] && source \$HOME/.bashrc_hoffman2

export PATH="$FULL_PATH"
export CONDA_DEFAULT_ENV="$ENV_NAME"
export CONDA_PREFIX="$ENV_PATH"
export CONDA_ENVS_PATH="$DEVBOX_HOME/conda/envs"
export CONDA_PKGS_DIRS="$DEVBOX_HOME/conda/pkgs"
export R_LIBS_USER="$DEVBOX_HOME/R/library"
export R_LIBS_SITE=""
export R_ENVIRON_USER="$DEVBOX_HOME/R/Renviron"
export RENV_PATHS_CACHE="$DEVBOX_HOME/renv-cache"
export PYTHONUSERBASE="$DEVBOX_HOME/pip"
export PYTHONNOUSERSITE=1
export NPM_CONFIG_PREFIX="$DEVBOX_HOME/npm-global"
export JUPYTER_DATA_DIR="$DEVBOX_HOME/jupyter"
export JUPYTER_RUNTIME_DIR="$DEVBOX_HOME/jupyter/runtime"

# Conda shell integration (enables conda activate)
eval "\$(conda shell.bash hook)" 2>/dev/null
conda activate "$ENV_PATH" 2>/dev/null

# ── Pretty prompt and colors ──
export TERM=xterm-256color
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias grep='grep --color=auto'

# Colored prompt: (env) user@host:dir$
#   env  = magenta, user@host = green, dir = blue
export PS1='\[\e[35m\]($ENV_NAME)\[\e[0m\] \[\e[32m\]\u@\h\[\e[0m\]:\[\e[34m\]\w\[\e[0m\]\$ '

# User customizations — this file is never overwritten by devbox
[[ -f "$DEVBOX_HOME/bashrc_user" ]] && source "$DEVBOX_HOME/bashrc_user"
RCEOF

# Create bashrc_user if it doesn't exist
if [[ ! -f "$DEVBOX_HOME/bashrc_user" ]]; then
    cat > "$DEVBOX_HOME/bashrc_user" <<'USERINIT'
# ~/.devbox/bashrc_user — Your personal shell customizations
# This file is sourced at the end of every devbox shell session.
# Unlike bashrc, this file is never overwritten by launch-devbox.sh.
#
# Examples:
#   alias ll='ls -lah'
#   export MY_PROJECT=/u/project/kruglyak/mydata
USERINIT
fi

# Bind the devbox bashrc so every shell inside the container gets the devbox
# PATH and environment — regardless of how RStudio/code-server launch terminals.
# profile.d = login shells, bash.bashrc = interactive non-login shells.
# The guard at the top of the file prevents double-sourcing.
BINDS+=("--bind" "$DEVBOX_BASHRC:/etc/profile.d/devbox.sh:ro")
BINDS+=("--bind" "$DEVBOX_BASHRC:/etc/bash.bashrc:ro")

# ── Helper: run inside container ─────────────────────────────────────────
run_in_container() {
    if [[ "$VERBOSE" == true ]]; then
        echo "[devbox] singularity exec ${GPU_FLAGS[*]+"${GPU_FLAGS[*]}"} ${BINDS[*]} $SIF $*"
    fi
    singularity exec \
        "${GPU_FLAGS[@]+"${GPU_FLAGS[@]}"}" \
        "${BINDS[@]}" \
        "$SIF" \
        "$@"
}

# ── Commands ─────────────────────────────────────────────────────────────
MODE="${1:-shell}"

case "$MODE" in
    setup)
        if [[ ! -f "$SIF" ]]; then
            echo "[error] Container not found at $SIF"
            echo "        Set DEVBOX_SIF or copy devbox-gpu.sif to ~/containers/"
            exit 1
        fi
        # Pass remaining args (e.g., --with bioinfo,ml) to the setup script
        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        run_in_container bash "$SCRIPT_DIR/devbox-setup.sh" "${@:2}"
        ;;

    shell)
        if [[ ! -d "$ENV_PATH" ]]; then
            echo "[error] Conda env '$ENV_NAME' not found at $ENV_PATH"
            if [[ "$ENV_NAME" == "devbox" ]]; then
                echo "        Run: $0 setup"
            else
                echo "        Create it: $0 shell  (then: mamba create -n $ENV_NAME ...)"
                echo "        Or use the default: unset DEVBOX_ENV && $0 shell"
            fi
            exit 1
        fi
        echo "Launching devbox shell ($ENV_NAME)..."
        singularity exec \
            "${GPU_FLAGS[@]+"${GPU_FLAGS[@]}"}" \
            "${BINDS[@]}" \
            "$SIF" \
            /bin/bash --rcfile "$DEVBOX_BASHRC"
        ;;

    code-server)
        echo "Starting code-server on port $CODE_SERVER_PORT..."
        print_tunnel "$CODE_SERVER_PORT"
        echo "  Password: ~/.config/code-server/config.yaml"

        # Write devbox-managed code-server settings for terminal and
        # language extension integration. User settings in settings.json
        # are preserved — devbox writes to a separate file that
        # code-server merges via machine settings.
        CS_MACHINE_DIR="$HOME/.local/share/code-server/Machine"
        mkdir -p "$CS_MACHINE_DIR"
        cat > "$CS_MACHINE_DIR/settings.json" <<CSEOF
{
    "terminal.integrated.profiles.linux": {
        "devbox": {
            "path": "/bin/bash",
            "args": ["--rcfile", "$DEVBOX_BASHRC"]
        }
    },
    "terminal.integrated.defaultProfile.linux": "devbox",
    "terminal.integrated.env.linux": {
        "PATH": "$FULL_PATH"
    },
    "r.rpath.linux": "$ENV_PATH/bin/R",
    "r.rterm.linux": "$ENV_PATH/bin/R",
    "r.lsp.path": "$ENV_PATH/bin/R",
    "python.defaultInterpreterPath": "$ENV_PATH/bin/python",
    "python.terminal.activateEnvironment": false,
    "jupyter.notebookFileRoot": "\${workspaceFolder}",
    "files.watcherExclude": {
        "**/.git/objects/**": true,
        "**/.git/subtree-cache/**": true,
        "**/node_modules/**": true,
        "**/.conda/**": true,
        "**/.devbox/conda/**": true,
        "**/.devbox/tmp/**": true,
        "**/results/**": true,
        "**/data/**": true,
        "**/.snakemake/**": true,
        "**/.Rproj.user/**": true,
        "**/renv/library/**": true,
        "**/__pycache__/**": true,
        "**/.ipynb_checkpoints/**": true
    },
    "files.exclude": {
        "**/.git": true,
        "**/.DS_Store": true
    },
    "files.enableTrash": false,
    "search.followSymlinks": false,
    "files.watcherPollingInterval": 5000,
    "files.legacyWatcher": true
}
CSEOF

        run_in_container \
            code-server \
                --bind-addr "0.0.0.0:${CODE_SERVER_PORT}" \
                --auth password \
                --disable-telemetry
        ;;

    rstudio)
        if [[ -z "${RSTUDIO_PASSWORD:-}" ]]; then
            RSTUDIO_PASSWORD=$(openssl rand -base64 15)
        fi
        export RSTUDIO_PASSWORD

        mkdir -p "$DEVBOX_HOME/rstudio/run" \
                 "$DEVBOX_HOME/rstudio/var-lib" \
                 "$DEVBOX_HOME/rstudio/db"

        cat > "$DEVBOX_HOME/rstudio/db/database.conf" <<DBEOF
provider=sqlite
directory=$DEVBOX_HOME/rstudio/var-lib
DBEOF

        # Tell RStudio to use the conda env's R
        export RSTUDIO_WHICH_R="$ENV_PATH/bin/R"

        # Create rsession wrapper that sets up the devbox environment
        # This ensures the R session has the correct PATH and library paths
        RSESSION_WRAPPER="$DEVBOX_HOME/rstudio/rsession.sh"
        cat > "$RSESSION_WRAPPER" <<RSEOF
#!/usr/bin/env bash
source "$DEVBOX_BASHRC"
exec /usr/lib/rstudio-server/bin/rsession "\$@"
RSEOF
        chmod +x "$RSESSION_WRAPPER"

        # Create a terminal shell wrapper that uses --rcfile to source ONLY
        # the devbox bashrc. Without this, the host ~/.bashrc runs after
        # /etc/bash.bashrc and clobbers the devbox PATH.
        TERMINAL_SHELL="$DEVBOX_HOME/rstudio/terminal-shell.sh"
        cat > "$TERMINAL_SHELL" <<TSHEOF
#!/bin/bash
exec bash --rcfile "$DEVBOX_BASHRC" "\$@"
TSHEOF
        chmod +x "$TERMINAL_SHELL"

        # RStudio terminals use $SHELL — point it to our wrapper
        set_container_env SHELL "$TERMINAL_SHELL"

        # Write rsession.conf
        cat > "$DEVBOX_HOME/rstudio/rsession.conf" <<RSCONFEOF
session-timeout-minutes=0
session-default-working-dir=$HOME
session-default-new-project-dir=$HOME
RSCONFEOF

        echo "Starting RStudio Server on port $RSTUDIO_PORT..."
        print_tunnel "$RSTUDIO_PORT"
        echo "  Username: ${USER}"
        echo "  Password: ${RSTUDIO_PASSWORD}"

        singularity exec \
            "${GPU_FLAGS[@]+"${GPU_FLAGS[@]}"}" \
            "${BINDS[@]}" \
            --bind "$DEVBOX_HOME/rstudio/run:/run" \
            --bind "$DEVBOX_HOME/rstudio/var-lib:/var/lib/rstudio-server" \
            --bind "$DEVBOX_HOME/rstudio/db/database.conf:/etc/rstudio/database.conf" \
            --bind "$DEVBOX_HOME/rstudio/rsession.conf:/etc/rstudio/rsession.conf" \
            "$SIF" \
            env "RSTUDIO_PASSWORD=$RSTUDIO_PASSWORD" \
            /usr/lib/rstudio-server/bin/rserver \
                --www-port "${RSTUDIO_PORT}" \
                --www-address 0.0.0.0 \
                --server-user "$(whoami)" \
                --rsession-which-r "$ENV_PATH/bin/R" \
                --rsession-path "$RSESSION_WRAPPER" \
                --auth-none 0 \
                --auth-pam-helper-path rstudio_auth
        ;;

    jupyter)
        echo "Starting JupyterLab on port $JUPYTER_PORT..."
        print_tunnel "$JUPYTER_PORT"

        # Configure Jupyter to use devbox bashrc for terminal sessions
        JUPYTER_CONFIG_DIR="$DEVBOX_HOME/jupyter/config"
        mkdir -p "$JUPYTER_CONFIG_DIR"
        cat > "$JUPYTER_CONFIG_DIR/jupyter_server_config.py" <<JPYEOF
c.ServerApp.terminado_settings = {
    "shell_command": ["/bin/bash", "--rcfile", "$DEVBOX_BASHRC"]
}
JPYEOF

        run_in_container \
            jupyter lab \
                --ip=0.0.0.0 \
                --port="${JUPYTER_PORT}" \
                --no-browser \
                --config="$JUPYTER_CONFIG_DIR/jupyter_server_config.py"
        ;;

    claude)
        run_in_container claude "${@:2}"
        ;;

    codex)
        run_in_container codex "${@:2}"
        ;;

    exec)
        run_in_container "${@:2}"
        ;;

    gpu-job)
        GPU_TYPE="${GPU_TYPE:-V100}"
        CORES="${CORES:-12}"
        MEM="${MEM:-5G}"
        VMEM="${VMEM:-60G}"
        TIME="${TIME:-8:00:00}"
        echo "Requesting GPU session: $GPU_TYPE, ${CORES} cores, ${MEM}/core, ${TIME}..."
        # SGE syntax — change DEVBOX_GPU_JOB_CMD for other schedulers
        "$GPU_JOB_CMD" -l "gpu,${GPU_TYPE},highp,h_data=${MEM},h_vmem=${VMEM},h_rt=${TIME}" \
             -pe "shared" "$CORES" -now n \
             "$0" shell
        ;;

    *)
        cat <<USAGE
Usage: $0 [--no-gpu|--cpu] [--verbose|-v] <command>

Commands:
  setup [--with profiles]   First-time setup (profiles: bioinfo, ml, r-extra)
  shell        Interactive shell
  code-server  VS Code in the browser
  rstudio      RStudio Server in the browser
  jupyter      JupyterLab in the browser
  claude       Claude Code CLI
  codex        Codex CLI
  gpu-job      Request GPU node, then launch shell
  exec <cmd>   Run arbitrary command

Adding packages (no rebuild needed):
  mamba install -n devbox <package>            # conda/bioconda
  pip install <package>                        # PyPI
  Rscript -e 'install.packages("pkg")'        # CRAN
  Rscript -e 'BiocManager::install("pkg")'    # Bioconductor
  npm install -g <package>                     # npm

Optional package profiles (can be installed anytime):
  $0 setup --with bioinfo    # pysam, pybedtools, scanpy, Bioconductor
  $0 setup --with ml         # PyTorch with CUDA support
  $0 setup --with r-extra    # tidyverse, Bioconductor, lme4, brms, etc.
  $0 setup --with all        # everything

Using a different conda environment:
  DEVBOX_ENV=myproject $0 shell

Environment variables:
  DEVBOX_SIF            .sif path (default: group shared)
  DEVBOX_ENV            conda env name (default: devbox)
  DEVBOX_LOGIN_HOST     login node hostname (default: hoffman2.idre.ucla.edu)
  DEVBOX_GPU_JOB_CMD    GPU job command (default: qrsh)
  DEVBOX_EXTRA_BINDS    extra bind mount paths, colon-separated
  CODE_SERVER_PORT      code-server port (default: 8080)
  RSTUDIO_PORT          RStudio port (default: 8787)
  RSTUDIO_PASSWORD      RStudio password (default: auto-generated)
  JUPYTER_PORT          Jupyter port (default: 8888)
  GPU_TYPE              GPU type for gpu-job (default: V100)
  CORES                 CPU cores for gpu-job (default: 12)
  MEM                   Memory per core for gpu-job (default: 5G)
  VMEM                  Virtual memory limit for gpu-job (default: 60G)
  TIME                  Wall time for gpu-job (default: 8:00:00)
USAGE
        exit 1
        ;;
esac
