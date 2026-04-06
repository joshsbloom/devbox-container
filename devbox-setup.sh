#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
# devbox-setup.sh — First-time setup for the devbox container
#
# Creates a conda environment with R, Python, Node.js, and core tools.
# Run this ONCE inside the container (via launch-devbox.sh setup).
#
# Optional profiles add domain-specific packages:
#   launch-devbox.sh setup --with bioinfo    # pysam, scanpy, Bioconductor
#   launch-devbox.sh setup --with ml         # PyTorch with CUDA
#   launch-devbox.sh setup --with r-extra    # tidyverse, lme4, brms, etc.
#   launch-devbox.sh setup --with all        # everything
#
# Profiles can also be installed later on an existing environment:
#   launch-devbox.sh setup --with ml
#
# After setup, customize freely:
#   mamba install -n devbox <package>
#   pip install <package>
#   install.packages("<package>")   # from within R
#   npm install -g <package>
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

DEVBOX_HOME="${DEVBOX_HOME:-$HOME/.devbox}"
ENV_NAME="devbox"
ENV_PATH="$DEVBOX_HOME/conda/envs/$ENV_NAME"

# ── Parse arguments ─────────────────────────────────────────────────────
PROFILES=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --with)
            shift
            IFS=',' read -ra PROFILES <<< "${1:-}"
            shift
            ;;
        *)
            echo "[setup] Unknown argument: $1"
            exit 1
            ;;
    esac
done

echo "=== DevBox setup for $(whoami) ==="
echo ""

# ── Create directory structure ───────────────────────────────────────────
mkdir -p "$DEVBOX_HOME/conda/envs"
mkdir -p "$DEVBOX_HOME/conda/pkgs"
mkdir -p "$DEVBOX_HOME/R/library"
mkdir -p "$DEVBOX_HOME/pip"
mkdir -p "$DEVBOX_HOME/npm-global"
mkdir -p "$DEVBOX_HOME/renv-cache"
mkdir -p "$DEVBOX_HOME/jupyter/runtime"
mkdir -p "$DEVBOX_HOME/rstudio/run"
mkdir -p "$DEVBOX_HOME/rstudio/var-lib"
mkdir -p "$DEVBOX_HOME/rstudio/db"
mkdir -p "$DEVBOX_HOME/config/code-server"
mkdir -p "$HOME/.local/share/code-server"

# ── Configure conda to use our paths ────────────────────────────────────
export CONDA_ENVS_PATH="$DEVBOX_HOME/conda/envs"
export CONDA_PKGS_DIRS="$DEVBOX_HOME/conda/pkgs"

# ── Create API key template ─────────────────────────────────────────────
if [[ ! -f "$DEVBOX_HOME/env" ]]; then
    cat > "$DEVBOX_HOME/env" <<'ENVEOF'
# DevBox API keys — edit with your actual keys
# Claude Code (https://console.anthropic.com/)
# export ANTHROPIC_API_KEY="sk-ant-XXXXXXXXXXXX"
# OpenAI Codex (https://platform.openai.com/)
# export OPENAI_API_KEY="sk-XXXXXXXXXXXX"
ENVEOF
    chmod 600 "$DEVBOX_HOME/env"
    echo "[setup] Created $DEVBOX_HOME/env — edit with your API keys"
fi

# ── Create R environment file ────────────────────────────────────────────
cat > "$DEVBOX_HOME/R/Renviron" <<RENVEOF
R_LIBS_USER=$DEVBOX_HOME/R/library
R_LIBS_SITE=
RENVEOF

# ── Profile installation functions ──────────────────────────────────────

install_bioinfo() {
    echo ""
    echo "[setup] Installing bioinformatics profile..."
    mamba install -y -p "$ENV_PATH" -c conda-forge -c bioconda \
        biopython pysam pybedtools scanpy anndata snakemake

    echo "[setup] Installing Bioconductor packages via conda..."
    mamba install -y -p "$ENV_PATH" -c conda-forge -c bioconda \
        bioconductor-genomicranges \
        bioconductor-biostrings \
        bioconductor-variantannotation \
        bioconductor-deseq2 \
        bioconductor-genomicfeatures \
        bioconductor-rtracklayer \
        bioconductor-genomicalignments \
        bioconductor-edger \
        bioconductor-limma \
        bioconductor-complexheatmap \
        bioconductor-rsamtools \
        bioconductor-bsgenome
}

install_ml() {
    echo ""
    echo "[setup] Installing machine learning profile..."
    mamba install -y -p "$ENV_PATH" -c pytorch -c nvidia -c conda-forge \
        pytorch \
        torchvision \
        pytorch-cuda=12.4
}

install_r_extra() {
    echo ""
    echo "[setup] Installing extended R profile..."
    mamba install -y -p "$ENV_PATH" -c conda-forge \
        r-devtools r-tidyverse r-data.table \
        r-rmarkdown r-knitr r-shiny r-reticulate \
        r-renv r-biocmanager r-remotes r-dt \
        r-hdf5r r-rcpp r-rcpparmadillo r-rcppeigen \
        r-matrix r-lme4 r-brms \
        r-ggrepel r-patchwork r-pheatmap r-viridis r-corrplot \
        r-future r-future.apply r-furrr r-arrow
}

# ── Tracking file for installed profiles ─────────────────────────────────
PROFILES_FILE="$DEVBOX_HOME/installed_profiles"
touch "$PROFILES_FILE"

mark_profile() {
    if ! grep -qx "$1" "$PROFILES_FILE" 2>/dev/null; then
        echo "$1" >> "$PROFILES_FILE"
    fi
}

is_profile_installed() {
    grep -qx "$1" "$PROFILES_FILE" 2>/dev/null
}

# ── Install profiles on existing env ────────────────────────────────────
if [[ -d "$ENV_PATH" ]] && [[ ${#PROFILES[@]} -gt 0 ]]; then
    echo "[setup] Conda environment '$ENV_NAME' exists. Installing additional profiles..."
    export PATH="$ENV_PATH/bin:$PATH"

    for profile in "${PROFILES[@]}"; do
        case "$profile" in
            all)
                install_bioinfo && mark_profile bioinfo
                install_ml && mark_profile ml
                install_r_extra && mark_profile r-extra
                ;;
            bioinfo)  install_bioinfo && mark_profile bioinfo ;;
            ml)       install_ml && mark_profile ml ;;
            r-extra)  install_r_extra && mark_profile r-extra ;;
            *)
                echo "[setup] Unknown profile: $profile (available: bioinfo, ml, r-extra, all)"
                exit 1
                ;;
        esac
    done

    conda clean -afy
    echo ""
    echo "=== Profiles installed! ==="
    exit 0
fi

# ── If env exists and no profiles requested, nothing to do ───────────────
if [[ -d "$ENV_PATH" ]] && [[ ${#PROFILES[@]} -eq 0 ]]; then
    echo "[setup] Conda environment '$ENV_NAME' already exists at $ENV_PATH"
    echo ""
    echo "  To add packages:    mamba install -n $ENV_NAME <package>"
    echo "  To add profiles:    launch-devbox.sh setup --with bioinfo,ml,r-extra"
    echo "  To rebuild from scratch:"
    echo "    mamba env remove -p $ENV_PATH"
    echo "    launch-devbox.sh setup"
    exit 0
fi

# ── Create conda environment (base) ────────────────────────────────────
echo ""
echo "[setup] Creating conda environment '$ENV_NAME'..."
echo "        This will take a few minutes."
echo ""

# Core: Python + R + Node.js + MKL as BLAS/LAPACK backend
# libblas=*=*mkl and liblapack=*=*mkl force conda to use Intel MKL
# instead of the default OpenBLAS — faster for linear algebra in both R and Python
mamba create -y -p "$ENV_PATH" -c conda-forge \
    python=3.12 \
    r-base=4.5 \
    nodejs=20 \
    "libblas=*=*mkl" \
    "liblapack=*=*mkl" \
    mkl-devel

echo "[setup] Installing core Python packages..."
mamba install -y -p "$ENV_PATH" -c conda-forge \
    numpy scipy pandas polars scikit-learn statsmodels \
    matplotlib seaborn plotnine plotly \
    jupyterlab ipykernel ipywidgets notebook \
    cookiecutter \
    black ruff mypy pytest pre-commit \
    httpx tqdm pyyaml click rich

echo "[setup] Installing core R packages..."
mamba install -y -p "$ENV_PATH" -c conda-forge \
    r-irkernel r-languageserver r-httpgd r-rlang

# C/C++ libraries needed inside the conda env so that conda's compiler
# can find them when compiling R packages from source (the system -dev
# libs in the container are not on conda gcc's search path)
echo "[setup] Installing C libraries for R package compilation..."
mamba install -y -p "$ENV_PATH" -c conda-forge -c bioconda \
    libxml2 libcurl openssl zlib bzip2 xz \
    htslib curl

echo "[setup] Installing CLI tools..."
export PATH="$ENV_PATH/bin:$PATH"
export NPM_CONFIG_PREFIX="$DEVBOX_HOME/npm-global"
npm install -g @anthropic-ai/claude-code
npm install -g @openai/codex

# Verify the binaries are where we expect
echo "[setup] Checking CLI installations..."
if [[ -x "$DEVBOX_HOME/npm-global/bin/claude" ]]; then
    echo "  claude: $DEVBOX_HOME/npm-global/bin/claude"
elif [[ -x "$ENV_PATH/bin/claude" ]]; then
    echo "  claude: $ENV_PATH/bin/claude (in conda env)"
else
    echo "  WARNING: claude binary not found"
    echo "  Try: npm install -g @anthropic-ai/claude-code"
fi
if [[ -x "$DEVBOX_HOME/npm-global/bin/codex" ]]; then
    echo "  codex:  $DEVBOX_HOME/npm-global/bin/codex"
elif [[ -x "$ENV_PATH/bin/codex" ]]; then
    echo "  codex:  $ENV_PATH/bin/codex (in conda env)"
else
    echo "  WARNING: codex binary not found"
fi

echo ""
echo "[setup] Claude Code and Codex CLI installed."
echo "        Authentication is required before first use."
echo "        Run these on a compute node:"
echo ""
echo "          launch-devbox.sh claude"
echo "          launch-devbox.sh codex"
echo ""
echo "        Each will prompt you to open a URL in your browser."
echo "        Credentials are cached in ~/.claude/ and ~/.codex/"
echo "        Alternatively, add API keys to ~/.devbox/env"
echo ""

echo "[setup] Registering R kernel for Jupyter..."
"$ENV_PATH/bin/Rscript" -e "IRkernel::installspec(user = TRUE)"

# ── Install requested profiles ──────────────────────────────────────────
for profile in "${PROFILES[@]}"; do
    case "$profile" in
        all)
            install_bioinfo && mark_profile bioinfo
            install_ml && mark_profile ml
            install_r_extra && mark_profile r-extra
            ;;
        bioinfo)  install_bioinfo && mark_profile bioinfo ;;
        ml)       install_ml && mark_profile ml ;;
        r-extra)  install_r_extra && mark_profile r-extra ;;
        *)
            echo "[setup] Unknown profile: $profile (available: bioinfo, ml, r-extra, all)"
            exit 1
            ;;
    esac
done

conda clean -afy

# ── Verify MKL linkage ──────────────────────────────────────────────────
echo ""
echo "[setup] Verifying BLAS/LAPACK backend..."
"$ENV_PATH/bin/Rscript" -e "
    si <- sessionInfo()
    cat('R BLAS:', si\$BLAS, '\n')
    cat('R LAPACK:', si\$LAPACK, '\n')
    if (grepl('mkl', si\$BLAS, ignore.case = TRUE)) {
        cat('MKL linked successfully.\n')
    } else {
        cat('WARNING: R does not appear to be linked to MKL.\n')
    }
"
"$ENV_PATH/bin/python" -c "
import numpy as np
config = np.show_config(mode='dicts')
print('NumPy BLAS:', config.get('blas_opt_info', {}).get('libraries', 'unknown'))
"

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Usage:"
echo "  launch-devbox.sh shell        # interactive shell"
echo "  launch-devbox.sh code-server  # VS Code in browser"
echo "  launch-devbox.sh rstudio      # RStudio in browser"
echo "  launch-devbox.sh jupyter      # JupyterLab in browser"
echo ""
echo "To add packages:"
echo "  mamba install -n devbox <package>           # conda package"
echo "  pip install <package>                       # Python package"
echo "  Rscript -e 'install.packages(\"pkg\")'      # R package"
echo "  npm install -g <package>                    # Node.js package"
echo ""
echo "Optional package profiles (install anytime):"
echo "  launch-devbox.sh setup --with bioinfo    # pysam, scanpy, Bioconductor"
echo "  launch-devbox.sh setup --with ml         # PyTorch with CUDA"
echo "  launch-devbox.sh setup --with r-extra    # tidyverse, lme4, brms, etc."
echo "  launch-devbox.sh setup --with all        # everything"
if [[ ${#PROFILES[@]} -gt 0 ]]; then
    echo ""
    echo "Installed profiles: ${PROFILES[*]}"
fi
echo ""
echo "To create additional conda environments:"
echo "  mamba create -n myproject python=3.12"
echo "  DEVBOX_ENV=myproject launch-devbox.sh shell"
echo ""
echo "Everything is stored in ~/.devbox/ — no container rebuild needed."
