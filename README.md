# pysci-ai-devenv-linux

Reproducible Python scientific computing and AI environment for Linux, built
with [devenv](https://devenv.sh) and Nix. One shell provides pinned CPython,
CUDA-enabled PyTorch, JupyterLab, and the scientific stack. Native libraries
come from Nix, Python packages from a single pip requirements file.

## Prerequisites

- Nix with flakes enabled
- [devenv](https://devenv.sh/getting-started/)
- direnv, optional, for automatic activation
- An NVIDIA driver on the host for GPU work (the driver never comes from Nix)

## Getting started

Enter the shell:

```sh
devenv shell
```

The first entry builds a venv from `requirements.txt` and installs everything.
Expect a long first run because the AI stack is large.

For automatic activation on `cd`, create a local `.envrc` (this repo
gitignores it):

```sh
eval "$(devenv direnvrc)"
use devenv
```

Then run `direnv allow`.

Verify the environment:

```sh
python verify.py
```

The script imports every top-level library and reports live CUDA access on the
GPU.

## What the shell provides

- CPython 3.13 through the `nixpkgs-python` input. devenv resolves the newest
  3.13 patch release. Edit `pythonVersion` in `devenv.nix` to try another
  minor version, for example `"3.14"`.
- A venv built from `requirements.txt`. devenv tracks a checksum of that file
  and the interpreter, so pip reruns only when one changes.
- Native libraries for compiled wheels: HDF5, NetCDF, GEOS, SDL2, OpenBLAS,
  and the image codecs. They are wired into both the build path and
  `LD_LIBRARY_PATH`, so wheels build and import against the same objects.
- CUDA toolkit and cuDNN from nixpkgs, exposed through `CUDA_HOME` for native
  CUDA builds. Torch and onnxruntime ship their own CUDA runtime inside their
  wheels.
- Temurin 21 for the Kotlin Jupyter kernel.
- uv and poetry for projects created inside the environment.

## GPU notes

PyTorch wheels come from the CUDA 13.0 index (`--extra-index-url` in
`requirements.txt`). Blackwell GPUs such as the RTX 5090 (sm_120) need CUDA
12.8 or newer. The default cu126 wheels from the PyTorch site lack sm_120
kernels. The host driver must be 595-series or newer.

## Updating packages

`requirements.txt` lists top-level packages without pins, so every venv
rebuild resolves the newest compatible versions. To upgrade an existing venv
in place:

```sh
pip install --upgrade -r requirements.txt
```

Nix inputs (nixpkgs and nixpkgs-python) are pinned by `devenv.lock`. Refresh
them with `devenv update`.

## Projects inside the environment

This shell is the fat base environment. Create real projects inside it with
uv or poetry and a portable lockfile. Such a project reproduces with
`uv sync` or `poetry install` on a machine that has no Nix.

## Repository layout

| File | Purpose |
| --- | --- |
| `devenv.nix` | The environment: packages, native libraries, venv wiring, env vars |
| `devenv.yaml` | Inputs: nixpkgs unstable and nixpkgs-python, with `allowUnfree` |
| `devenv.lock` | The pin for those inputs |
| `requirements.txt` | Top-level Python packages, resolved by pip |
| `verify.py` | Import check for every library plus CUDA status |
