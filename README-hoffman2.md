# Best Practices for Developing on Hoffman2

This guide covers how to work effectively on Hoffman2, with an emphasis on
managing storage, understanding the filesystem, and avoiding common pitfalls.

---

## Hoffman2 filesystem layout

Hoffman2 has three main storage areas. Understanding where to put things
is critical — running out of home directory quota is the most common
problem new users hit.

```
/u/home/<first-letter>/<username>/     Your home directory (small, backed up)
/u/scratch/<username>/                 Temporary fast storage (large, NOT backed up)
/u/project/<PI-name>/                  Shared group storage (large, backed up)
```

### Home directory (`$HOME` = `/u/home/...`)

- **Quota: ~20 GB** (varies by account)
- **Backed up:** Yes
- **Purpose:** Config files, scripts, small code repos

Your home directory is small. It fills up fast once you install conda
environments, R packages, and npm tools. DevBox puts everything under
`~/.devbox/`, which can easily reach 10-20 GB with a full environment.

**Check your usage:**

    myquota

This shows your current home directory usage and quota. Run this regularly.

**What belongs here:**
- Shell config (`.bashrc`, `.ssh/`)
- Small code repositories
- DevBox scripts and config (`~/bin/`, `~/.devbox/env`)
- API keys and credentials

**What does NOT belong here:**
- Data files (FASTQ, BAM, VCF, CSV, HDF5, etc.)
- Large analysis outputs or results
- Conda package cache (move to scratch — see below)
- Anything over a few hundred MB

### Scratch directory (`/u/scratch/$USER/`)

- **Quota: ~2 TB** (varies)
- **Backed up:** No
- **Purge policy:** Files not accessed for ~14 days may be deleted
- **Purpose:** Active computation, temporary data, intermediate files

Scratch is fast, large, and disposable. Use it for anything that is
generated during analysis and can be regenerated if lost.

**What belongs here:**
- Intermediate analysis files
- Snakemake working directories
- Temporary datasets being processed
- Singularity cache (speeds up container loading)
- Conda package cache (saves home directory space)

**What does NOT belong here:**
- Anything you can't regenerate (raw sequencing data, final results)
- Code repositories
- Long-term reference data

### Project directory (`/u/project/<PI-name>/`)

- **Quota:** Varies by group allocation (typically hundreds of GB to TB)
- **Backed up:** Yes
- **Purpose:** Shared data, reference genomes, final results

This is your group's shared storage. It's large, persistent, and visible
to everyone in the group. Use it for data that multiple people need access
to or that must not be lost.

**What belongs here:**
- Raw data (FASTQ, BAM, etc.)
- Reference genomes and annotations
- Final analysis results and figures
- Shared containers (the devbox `.sif` lives here)
- Shared scripts and pipelines

**Typical structure:**

    /u/project/kruglyak/
    ├── PUBLIC_SHARED/          # Shared tools, containers
    │   └── containers/
    │       ├── devbox-gpu.sif
    │       ├── launch-devbox.sh
    │       └── devbox-setup.sh
    ├── <username>/             # Your personal project space
    │   ├── data/               # Your raw data
    │   ├── results/            # Final analysis outputs
    │   └── references/         # Reference genomes, annotations
    └── shared_data/            # Data shared across the group

---

## Keeping your home directory under quota

The most common issue on Hoffman2 is running out of home directory space.
Here's how to prevent it.

### Move the conda package cache to scratch

The conda package cache (`~/.devbox/conda/pkgs/`) stores downloaded
packages and can grow to several GB. Move it to scratch:

    # Create a cache directory on scratch
    mkdir -p /u/scratch/$USER/conda-pkgs

    # Replace the cache directory with a symlink
    rm -rf ~/.devbox/conda/pkgs
    ln -sf /u/scratch/$USER/conda-pkgs ~/.devbox/conda/pkgs

### Move the Singularity cache to scratch

Add this to your `~/.bashrc` so Singularity doesn't fill your home
directory with temporary files:

    export SINGULARITY_TMPDIR=/u/scratch/$USER/singularity-tmp
    export SINGULARITY_CACHEDIR=/u/scratch/$USER/singularity-cache
    mkdir -p $SINGULARITY_TMPDIR $SINGULARITY_CACHEDIR

### Keep data on project or scratch

Never store data files in your home directory. When working on an analysis:

    # Work from your project directory
    cd /u/project/kruglyak/$USER/my-analysis

    # Or from scratch for temporary work
    cd /u/scratch/$USER/my-analysis

    # Launch devbox from there — it will open in that directory
    launch-devbox.sh shell

### Monitor your usage

    # Check home directory quota
    myquota

    # Find large files in your home directory
    du -sh ~/.devbox/conda/pkgs/
    du -sh ~/.devbox/conda/envs/devbox/
    du -sh ~/.devbox/R/library/
    du -sh ~/.devbox/npm-global/

    # Find unexpectedly large files
    find ~ -maxdepth 3 -size +100M -exec ls -lh {} \;

### Clean up conda cache periodically

From inside a devbox shell:

    conda clean -afy

This removes downloaded tarballs and unused package caches.

---

## Organizing your work

### Recommended project structure

Keep code in your home directory and data on project/scratch:

    # Code (small, version-controlled) — home directory
    ~/projects/my-analysis/
    ├── Snakefile
    ├── scripts/
    ├── notebooks/
    └── .git/

    # Data (large, not version-controlled) — project directory
    /u/project/kruglyak/$USER/my-analysis/
    ├── data/           # raw input data
    ├── results/        # final outputs
    └── figures/        # publication figures

    # Intermediate files (large, disposable) — scratch
    /u/scratch/$USER/my-analysis/
    ├── aligned/        # BAM files from alignment step
    ├── counts/         # feature counts
    └── tmp/            # throwaway intermediate files

Use **symlinks** to make this easy to navigate:

    cd ~/projects/my-analysis
    ln -sf /u/project/kruglyak/$USER/my-analysis/data data
    ln -sf /u/project/kruglyak/$USER/my-analysis/results results
    ln -sf /u/scratch/$USER/my-analysis scratch

Now from your project directory you can reference `data/sample.fastq`
and `results/output.csv` without typing the full paths.

### Use Snakemake with scratch for intermediate files

If you're using Snakemake, point intermediate outputs to scratch:

```python
# In your Snakefile
SCRATCH = f"/u/scratch/{os.environ['USER']}/my-pipeline"

rule align:
    input: "data/{sample}.fastq.gz"
    output: f"{SCRATCH}/aligned/{{sample}}.bam"
    shell: "bwa mem ref.fa {input} | samtools sort -o {output}"

rule count:
    input: f"{SCRATCH}/aligned/{{sample}}.bam"
    output: "results/{sample}.counts.tsv"   # final output goes to project
    shell: "featureCounts -a genes.gtf -o {output} {input}"
```

---

## Job scheduler tips

### Request appropriate resources

A good default for interactive development:

    qrsh -l highp,h_rt=8:00:00,h_data=5G,h_vmem=60G -pe shared 12 -now n

What each flag means:
- `highp` — high-priority queue (your group's owned nodes, faster start)
- `h_rt=8:00:00` — 8 hours of wall time (real clock time before the job is killed)
- `h_data=5G` — 5 GB physical memory per core (60 GB total with 12 cores)
- `h_vmem=60G` — 60 GB virtual memory limit for the whole job
- `-pe shared 12` — 12 CPU cores
- `-now n` — wait in the queue instead of failing if no nodes are free

For GPU work, add `gpu,V100` (or another GPU type):

    qrsh -l gpu,V100,highp,h_rt=8:00:00,h_data=5G,h_vmem=60G -pe shared 12 -now n

**If you're waiting too long in the queue**, reduce resources. Try in order:
1. Fewer cores: `-pe shared 4` instead of 12
2. Less memory: `h_data=4G,h_vmem=20G`
3. Shorter wall time: `h_rt=4:00:00`
4. Drop `highp` (uses the general queue — more nodes available but lower priority)

### Use batch jobs for long-running work

Interactive sessions (`qrsh`) are great for development but limited by
wall time and your SSH connection. For long analyses, submit batch jobs:

    # Create a job script
    cat > my_job.sh << 'EOF'
    #!/bin/bash
    #$ -l h_data=8G,h_rt=24:00:00
    #$ -pe shared 4
    #$ -cwd
    #$ -o logs/$JOB_ID.out
    #$ -e logs/$JOB_ID.err

    launch-devbox.sh exec python scripts/my_analysis.py
    EOF

    mkdir -p logs
    qsub my_job.sh

Check job status:

    qstat                    # your jobs
    qstat -u '*'             # all jobs (see cluster load)
    qacct -j <job-id>        # details of a completed job

---

## Working with devbox on Hoffman2

### Where to launch devbox from matters

DevBox opens in whatever directory you're in when you run the command. Work
from your project or scratch directory, not your home:

    # Good — you'll be in your project directory inside the container
    cd /u/project/kruglyak/$USER/my-analysis
    launch-devbox.sh shell

    # Also good — working from scratch for temporary analysis
    cd /u/scratch/$USER/temp-analysis
    launch-devbox.sh shell

### All three filesystems are accessible inside the container

DevBox bind-mounts home, scratch, and project directories into the
container. You can access all three from inside a devbox shell:

    ls ~/                              # home directory
    ls /u/scratch/$USER/               # scratch
    ls /u/project/kruglyak/            # project

### Install packages to the right place

Packages installed inside the container go into `~/.devbox/` (on your home
directory). If your home is getting full:

1. Move the conda cache to scratch (see above)
2. Clean up after installs: `conda clean -afy`
3. Prefer mamba/conda packages over pip when possible — pip installs can
   scatter files across `~/.devbox/pip/`
