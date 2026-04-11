#!/usr/bin/env bash
set -euo pipefail

echo "==> Setting up minimal macOS bioinformatics environment"

have() {
  command -v "$1" >/dev/null 2>&1
}

append_if_missing() {
  local line="$1"
  local file="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  grep -Fqs "$line" "$file" || echo "$line" >> "$file"
}

detect_shell_rc() {
  if [[ "${SHELL:-}" == *bash ]]; then
    echo "${HOME}/.bashrc"
  else
    echo "${HOME}/.zshrc"
  fi
}

brew_prefix_for_arch() {
  if [[ "$(uname -m)" == "arm64" ]]; then
    echo "/opt/homebrew"
  else
    echo "/usr/local"
  fi
}

SHELL_RC="$(detect_shell_rc)"
BREW_PREFIX="$(brew_prefix_for_arch)"
ENV_NAME="bio"

# -----------------------------
# Xcode Command Line Tools
# -----------------------------
if ! xcode-select -p >/dev/null 2>&1; then
  echo "==> Xcode Command Line Tools not found"
  echo "==> Requesting install"
  xcode-select --install || true
  echo "Please finish the install, then rerun this script."
  exit 1
else
  echo "==> Xcode Command Line Tools already present"
fi

# -----------------------------
# Homebrew
# -----------------------------
if ! have brew; then
  echo "==> Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  echo "==> Homebrew already installed: $(command -v brew)"
fi

if [[ -x "${BREW_PREFIX}/bin/brew" ]]; then
  eval "$("${BREW_PREFIX}/bin/brew" shellenv)"
  append_if_missing "eval \"\$(${BREW_PREFIX}/bin/brew shellenv)\"" "$SHELL_RC"
else
  echo "ERROR: brew not found at expected path ${BREW_PREFIX}/bin/brew"
  exit 1
fi

echo "==> Updating Homebrew metadata"
brew update

# -----------------------------
# Core packages
# -----------------------------
for pkg in git wget curl; do
  if brew list "$pkg" >/dev/null 2>&1; then
    echo "==> $pkg already installed"
  else
    echo "==> Installing $pkg"
    brew install "$pkg"
  fi
done

# -----------------------------
# iTerm2
# -----------------------------
if brew list --cask iterm2 >/dev/null 2>&1; then
  echo "==> iTerm2 already installed"
else
  echo "==> Installing iTerm2"
  brew install --cask iterm2
fi

# -----------------------------
# R
# -----------------------------
if have R; then
  echo "==> R already installed: $(command -v R)"
else
  echo "==> Installing R"
  brew install r
fi

# -----------------------------
# Conda / Miniforge
# -----------------------------
CONDA_BIN=""

if have conda; then
  CONDA_BIN="$(command -v conda)"
  echo "==> Existing conda found: ${CONDA_BIN}"
elif [[ -x "${HOME}/miniforge3/bin/conda" ]]; then
  CONDA_BIN="${HOME}/miniforge3/bin/conda"
  echo "==> Existing Miniforge conda found: ${CONDA_BIN}"
else
  echo "==> Installing Miniforge"
  brew install --cask miniforge

  if have conda; then
    CONDA_BIN="$(command -v conda)"
    echo "==> Conda found after install: ${CONDA_BIN}"
  elif [[ -x "/opt/homebrew/bin/conda" ]]; then
    CONDA_BIN="/opt/homebrew/bin/conda"
    echo "==> Conda found after install: ${CONDA_BIN}"
  elif [[ -x "/usr/local/bin/conda" ]]; then
    CONDA_BIN="/usr/local/bin/conda"
    echo "==> Conda found after install: ${CONDA_BIN}"
  else
    echo "ERROR: Miniforge installed but conda not found"
    exit 1
  fi
fi

# Initialize conda only if shell rc does not already mention conda init
if ! grep -Eq 'conda init|miniforge3/bin/conda|# >>> conda initialize >>>' "$SHELL_RC" 2>/dev/null; then
  echo "==> Initializing conda for future shells"
  "$CONDA_BIN" init "$(basename "${SHELL:-/bin/zsh}")" || true
else
  echo "==> Shell already appears configured for conda"
fi

# Load conda into current script session
eval "$("$CONDA_BIN" shell.bash hook)"

# -----------------------------
# Conda channels
# -----------------------------
echo "==> Configuring conda channels"
conda config --remove-key channels >/dev/null 2>&1 || true
conda config --add channels conda-forge
conda config --add channels bioconda
conda config --set channel_priority strict

# -----------------------------
# Conda environment
# -----------------------------
if conda env list | awk '{print $1}' | grep -qx "${ENV_NAME}"; then
  echo "==> Conda environment '${ENV_NAME}' already exists"
else
  echo "==> Creating conda environment '${ENV_NAME}'"
  conda create -y -n "${ENV_NAME}" -c conda-forge -c bioconda \
    python=3.12 \
    jupyterlab \
    notebook \
    ipykernel \
    numpy \
    pandas \
    scipy \
    matplotlib \
    scikit-learn \
    biopython \
    pysam
fi

echo "==> Activating conda environment '${ENV_NAME}'"
conda activate "${ENV_NAME}"

# Ensure core packages are present if env already existed
echo "==> Ensuring core Python packages are installed in '${ENV_NAME}'"
conda install -y -n "${ENV_NAME}" -c conda-forge -c bioconda \
  python=3.12 \
  jupyterlab \
  notebook \
  ipykernel \
  numpy \
  pandas \
  scipy \
  matplotlib \
  scikit-learn \
  biopython \
  pysam



# -----------------------------
# Python Jupyter kernel
# -----------------------------
if jupyter kernelspec list 2>/dev/null | grep -qE "^ *${ENV_NAME} "; then
  echo "==> Jupyter Python kernel '${ENV_NAME}' already registered"
else
  echo "==> Registering Jupyter Python kernel '${ENV_NAME}'"
  python -m ipykernel install --user --name "${ENV_NAME}" --display-name "Python (${ENV_NAME})"
fi

# -----------------------------
# R packages
# -----------------------------
echo "==> Ensuring R packages are installed"
Rscript - <<'EOF'
options(repos = c(CRAN = "https://cloud.r-project.org"))

needed <- c("IRkernel", "tidyverse", "data.table", "BiocManager")
installed <- rownames(installed.packages())
to_install <- setdiff(needed, installed)

if (length(to_install) > 0) {
  install.packages(to_install)
} else {
  message("R CRAN packages already installed")
}

installed <- rownames(installed.packages())
if (!("Biostrings" %in% installed) || !("GenomicRanges" %in% installed)) {
  if (!("BiocManager" %in% installed)) {
    install.packages("BiocManager")
  }
  BiocManager::install(c("Biostrings", "GenomicRanges"), ask = FALSE, update = FALSE)
} else {
  message("Bioconductor packages already installed")
}
EOF

# -----------------------------
# R kernel for Jupyter
# -----------------------------
if jupyter kernelspec list 2>/dev/null | grep -qE '^ *ir '; then
  echo "==> Jupyter R kernel already registered"
else
  echo "==> Registering Jupyter R kernel"
  Rscript -e 'IRkernel::installspec(user = TRUE)'
fi

# -----------------------------
# Codex CLI
# -----------------------------
if have codex; then
  echo "==> Codex already installed: $(command -v codex)"
else
  echo "==> Installing Codex CLI"
  brew install codex
fi

# -----------------------------
# Claude CLI
# -----------------------------
if have claude; then
  echo "==> Claude CLI already installed: $(command -v claude)"
else
  echo "==> Installing Claude CLI"
  curl -fsSL https://claude.ai/install.sh | bash
fi

# -----------------------------
# Project directories
# -----------------------------
for d in "${HOME}/code" "${HOME}/data" "${HOME}/notebooks"; do
  if [[ -d "$d" ]]; then
    echo "==> Directory already exists: $d"
  else
    echo "==> Creating directory: $d"
    mkdir -p "$d"
  fi
done

# -----------------------------
# Helpful shell defaults
# -----------------------------
append_if_missing 'export EDITOR=vim' "$SHELL_RC"
append_if_missing 'export VISUAL=vim' "$SHELL_RC"
append_if_missing 'alias ll="ls -lah"' "$SHELL_RC"

# -----------------------------
# Done
# -----------------------------
echo
echo "==> Setup complete"
echo
echo "Open a new terminal or run:"
echo "  source \"$SHELL_RC\""
echo "  conda activate ${ENV_NAME}"
echo "  jupyter lab"
echo
echo "Useful checks:"
echo "  which python"
echo "  python --version"
echo "  which R"
echo "  R --version"
echo "  which jupyter"
echo "  jupyter kernelspec list"
echo "  which codex"
echo "  which claude"
