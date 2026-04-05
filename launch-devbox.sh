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
#   ./launch-devbox.sh setup          # first-time setup (creates conda env)
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
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────
SIF="${DEVBOX_SIF:-/u/project/kruglyak/PUBLIC_SHARED/containers/devbox-gpu.sif}"

DEVBOX_HOME="$HOME/.devbox"
ENV_PATH="$DEVBOX_HOME/conda/envs/devbox"
COMPUTE_NODE=$(hostname)
LOGIN_HOST="hoffman2.idre.ucla.edu"

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
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --no-gpu|--cpu) FORCE_NO_GPU=true ;;
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

# Activate the devbox conda env by prepending it to PATH
if [[ -d "$ENV_PATH/bin" ]]; then
    DEVBOX_PATH="$ENV_PATH/bin:$DEVBOX_HOME/npm-global/bin:/opt/miniforge3/bin:/opt/code-server/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    # Only set PATH inside the container — don't clobber host PATH
    export SINGULARITYENV_PATH="$DEVBOX_PATH"
    export APPTAINERENV_PATH="$DEVBOX_PATH"
    set_container_env CONDA_DEFAULT_ENV "devbox"
    set_container_env CONDA_PREFIX "$ENV_PATH"
fi

# ── Write shell init file for code-server / RStudio terminals ────────────
# code-server and RStudio spawn their own terminal shells that don't
# inherit SINGULARITYENV_ variables. This init file ensures every
# new terminal gets the devbox environment.
DEVBOX_BASHRC="$DEVBOX_HOME/bashrc"
cat > "$DEVBOX_BASHRC" <<RCEOF
# DevBox shell init — auto-generated by launch-devbox.sh
# Source the real bashrc first if it exists
[[ -f /etc/bash.bashrc ]] && source /etc/bash.bashrc
[[ -f \$HOME/.bashrc_hoffman2 ]] && source \$HOME/.bashrc_hoffman2

export PATH="$DEVBOX_PATH"
export CONDA_DEFAULT_ENV="devbox"
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

export PS1="(devbox) \u@\h:\w\$ "
RCEOF

# ── Helper: run inside container ─────────────────────────────────────────
run_in_container() {
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
        # Run the setup script inside the container
        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        run_in_container bash "$SCRIPT_DIR/devbox-setup.sh"
        ;;

    shell)
        if [[ ! -d "$ENV_PATH" ]]; then
            echo "[error] Conda env not found. Run: $0 setup"
            exit 1
        fi
        echo "Launching devbox shell..."
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

        # Write code-server settings:
        # - Terminal uses devbox bashrc
        # - R/Python extensions point to conda env
        # - File watcher exclusions to prevent inotify exhaustion
        #   (ptyHost crashes when inotify limits are hit on large dirs)
        mkdir -p "$HOME/.local/share/code-server/User"
        cat > "$HOME/.local/share/code-server/User/settings.json" <<CSEOF
{
    "terminal.integrated.profiles.linux": {
        "devbox": {
            "path": "/bin/bash",
            "args": ["--rcfile", "$DEVBOX_BASHRC"]
        }
    },
    "terminal.integrated.defaultProfile.linux": "devbox",
    "terminal.integrated.env.linux": {
        "PATH": "$DEVBOX_PATH"
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
        # This ensures both the R session and the RStudio terminal
        # have the correct PATH and library paths
        RSESSION_WRAPPER="$DEVBOX_HOME/rstudio/rsession.sh"
        cat > "$RSESSION_WRAPPER" <<RSEOF
#!/usr/bin/env bash
source "$DEVBOX_BASHRC"
exec /usr/lib/rstudio-server/bin/rsession "\$@"
RSEOF
        chmod +x "$RSESSION_WRAPPER"

        # Write rsession.conf that points to our wrapper and bashrc
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
        echo "[devbox] Note: requires internet (may not work on compute nodes)"
        run_in_container claude "${@:2}"
        ;;

    codex)
        echo "[devbox] Note: requires internet (may not work on compute nodes)"
        run_in_container codex "${@:2}"
        ;;

    exec)
        run_in_container "${@:2}"
        ;;

    gpu-job)
        GPU_TYPE="${GPU_TYPE:-P4}"
        CORES="${CORES:-4}"
        MEM="${MEM:-16G}"
        TIME="${TIME:-4:00:00}"
        echo "Requesting GPU session: $GPU_TYPE, ${CORES} cores, ${MEM}/core, ${TIME}..."
        qrsh -l "gpu,${GPU_TYPE},h_data=${MEM},h_rt=${TIME}" \
             -pe "shared" "$CORES" \
             "$0" shell
        ;;

    *)
        cat <<USAGE
Usage: $0 [--no-gpu|--cpu] <command>

Commands:
  setup        First-time setup — creates conda env with R, Python, Node.js
  shell        Interactive shell
  code-server  VS Code in the browser
  rstudio      RStudio Server in the browser
  jupyter      JupyterLab in the browser
  claude       Claude Code CLI (needs internet)
  codex        Codex CLI (needs internet)
  gpu-job      Request GPU node, then launch shell
  exec <cmd>   Run arbitrary command

Adding packages (no rebuild needed):
  mamba install -n devbox <package>            # conda/bioconda
  pip install <package>                        # PyPI
  Rscript -e 'install.packages("pkg")'        # CRAN
  Rscript -e 'BiocManager::install("pkg")'    # Bioconductor
  npm install -g <package>                     # npm

Environment variables:
  DEVBOX_SIF          .sif path (default: group shared or ~/containers/)
  CODE_SERVER_PORT    code-server port (default: 8080)
  RSTUDIO_PORT        RStudio port (default: 8787)
  RSTUDIO_PASSWORD    RStudio password (default: auto-generated)
  JUPYTER_PORT        Jupyter port (default: 8888)
  GPU_TYPE            GPU type for gpu-job (default: P4)
  CORES               CPU cores for gpu-job (default: 4)
  MEM                 Memory per core for gpu-job (default: 16G)
  TIME                Wall time for gpu-job (default: 4:00:00)
USAGE
        exit 1
        ;;
esac
