#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
# devbox-setup.sh — First-time setup for the devbox container
#
# Creates a conda environment with R, Python, Node.js, and common packages.
# Run this ONCE inside the container (via launch-devbox.sh setup).
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

echo "=== DevBox first-time setup for $(whoami) ==="
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

# ── Check if env already exists ──────────────────────────────────────────
if [[ -d "$ENV_PATH" ]]; then
    echo "[setup] Conda environment '$ENV_NAME' already exists at $ENV_PATH"
    echo "        To rebuild: mamba env remove -n $ENV_NAME && ./devbox-setup.sh"
    exit 0
fi

# ── Create conda environment ────────────────────────────────────────────
echo ""
echo "[setup] Creating conda environment '$ENV_NAME'..."
echo "        This will take 10-20 minutes on first run."
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

echo "[setup] Installing Python packages..."
mamba install -y -p "$ENV_PATH" -c pytorch -c nvidia -c conda-forge \
    pytorch \
    torchvision \
    pytorch-cuda=12.4 \
    numpy scipy pandas polars scikit-learn statsmodels \
    matplotlib seaborn plotnine plotly \
    jupyterlab ipykernel ipywidgets notebook \
    cookiecutter \
    black ruff mypy pytest pre-commit \
    httpx tqdm pyyaml click rich

echo "[setup] Installing bioinformatics packages..."
mamba install -y -p "$ENV_PATH" -c conda-forge -c bioconda \
    biopython pysam pybedtools scanpy anndata snakemake

echo "[setup] Installing R packages..."
mamba install -y -p "$ENV_PATH" -c conda-forge \
    r-devtools r-tidyverse r-data.table \
    r-rmarkdown r-knitr r-shiny r-reticulate \
    r-irkernel r-renv r-biocmanager r-remotes r-dt \
    r-hdf5r r-rcpp r-rcpparmadillo r-rcppeigen \
    r-matrix r-lme4 r-brms \
    r-ggrepel r-patchwork r-pheatmap r-viridis r-corrplot \
    r-future r-future.apply r-furrr r-arrow \
    r-languageserver r-httpgd r-rlang

# C/C++ libraries needed inside the conda env so that conda's compiler
# can find them when compiling R packages from source (the system -dev
# libs in the container are not on conda gcc's search path)
echo "[setup] Installing C libraries for R package compilation..."
mamba install -y -p "$ENV_PATH" -c conda-forge \
    libxml2 libcurl openssl zlib bzip2 xz \
    htslib curl

echo "[setup] Installing Bioconductor packages via conda..."
# Install as many Bioconductor packages as possible via conda to avoid
# compilation issues with conda's gcc vs system libraries
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

echo "[setup] Installing CLI tools..."
# Activate env to use its npm and set npm global prefix
# to match what launch-devbox.sh expects at runtime
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
echo "        Run these on a LOGIN NODE (needs internet):"
echo ""
echo "          ~/bin/launch-devbox.sh claude"
echo "          ~/bin/launch-devbox.sh codex"
echo ""
echo "        Each will prompt you to open a URL in your browser."
echo "        Credentials are cached in ~/.claude/ and ~/.codex/"
echo "        Alternatively, add API keys to ~/.devbox/env"
echo ""

echo "[setup] Registering R kernel for Jupyter..."
"$ENV_PATH/bin/Rscript" -e "IRkernel::installspec(user = TRUE)"

echo "[setup] Bioconductor packages installed via conda (above)."
echo "        To add more Bioconductor packages:"
echo "          mamba install -n devbox -c bioconda bioconductor-<pkgname>"
echo "        Or from R:"
echo "          BiocManager::install('PkgName')"

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
echo "  ./launch-devbox.sh shell        # interactive shell"
echo "  ./launch-devbox.sh code-server  # VS Code in browser"
echo "  ./launch-devbox.sh rstudio      # RStudio in browser"
echo "  ./launch-devbox.sh jupyter      # JupyterLab in browser"
echo ""
echo "To add packages:"
echo "  mamba install -n devbox <package>           # conda package"
echo "  pip install <package>                       # Python package"
echo "  Rscript -e 'install.packages(\"pkg\")'      # R package"
echo "  npm install -g <package>                    # Node.js package"
echo ""
echo "Everything is stored in ~/.devbox/ — no container rebuild needed."
