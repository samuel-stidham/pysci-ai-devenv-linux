{ pkgs, lib, config, inputs, ... }:

let
  # ── PYTHON VERSION ─────────────────────────────────────────────────
  # Single source of truth. Change this one line to "3.14" to test
  # forward compatibility, then re-enter the shell. nixpkgs-python (wired
  # up in devenv.yaml) resolves the exact CPython build, so both "3.13"
  # and "3.14" work with no other edits. The venv is rebuilt whenever the
  # interpreter changes, so switching versions reinstalls cleanly.
  pythonVersion = "3.13";

  # ── NATIVE LIBRARIES ───────────────────────────────────────────────
  # pip-built extensions link and dlopen against these. They are declared
  # once here, then fed to BOTH `packages` (so headers and shared objects
  # exist when a wheel builds from source) and LD_LIBRARY_PATH (so the
  # same .so files are found at import time). A wheel that builds fine but
  # cannot dlopen its dependency fails at `import`, not at install, so the
  # runtime path matters as much as the build path.
  #
  # Note: torch, torchvision, torchaudio, and onnxruntime-gpu ship their
  # own bundled CUDA runtime inside the wheel. cudatoolkit and cudnn below
  # are for CUDA_HOME and for any project that compiles its own CUDA code,
  # not for driving torch. The GPU driver itself is not a Nix package; it
  # comes from the host (see nvidia-smi in enterShell).
  nativeLibs = with pkgs; [
    stdenv.cc.cc.lib                     # libstdc++, needed by every compiled extension
    zlib
    hdf5                                 # h5py
    netcdf                               # netcdf4
    geos                                 # shapely
    gmp mpfr libmpc                      # gmpy2
    SDL2 SDL2_image SDL2_mixer SDL2_ttf  # pygame, kivy
    libjpeg libpng libtiff freetype      # pillow
    openblas                             # numpy, scipy BLAS/LAPACK backend
    cudaPackages.cudatoolkit
    cudaPackages.cudnn
  ];
in
{
  # Build toolchain plus the two Python project managers. uv and poetry
  # live here, NOT in the pip requirements, on purpose. This devenv shell is
  # the fat base environment holding every scientific and AI library. An
  # individual project created inside it uses uv or poetry with a portable
  # lockfile, so the project reproduces with `uv sync` or `poetry install`
  # on a machine that has no Nix at all. That portability is the point:
  # Nix is not available everywhere, the project's own lockfile is.
  packages = with pkgs; [
    gcc
    gnumake
    cmake
    pkg-config
    ffmpeg
    uv
    poetry

    # JVM for the kotlin-jupyter-kernel in the core requirements. That kernel is
    # a pip package that shells out to `java`, and it found one before this line
    # existed: /home/…/.nix-profile/bin/java, temurin 21.0.11, leaking in from
    # the home-manager user profile. Working by accident is the problem. This
    # shell claims to be self-contained, and on any machine without that
    # profile the kernel would have died with no java on PATH at all.
    #
    # 21 to match the default JDK in nix-config/home/jdks.nix, so a notebook
    # and the rest of the machine agree on the JVM.
    temurin-bin-21
  ] ++ nativeLibs;

  languages.python = {
    enable = true;
    version = pythonVersion;

    # Many wheels here (torch, onnxruntime-gpu, faiss) are manylinux
    # builds that expect the manylinux compatibility libraries. Without
    # this they install but fail to load on Nix.
    manylinux.enable = true;

    # The base environment. devenv creates the venv under $DEVENV_STATE,
    # activates it on shell entry, and runs pip against the requirements
    # below. It tracks a checksum of the content and the interpreter, so
    # pip only reruns when one of them actually changes.
    #
    # The package lists live in the pysci-core input, split into a
    # cross-platform core plus one small delta per platform. The local
    # requirements.txt is gone so there is no second place to edit and
    # nothing to drift. Change packages over there, then `devenv update`
    # here pulls the new pin. The concatenation is plain string glue:
    # pip reads the core list, then the Linux delta carrying the cu130
    # index line and the -gpu wheel variants.
    venv = {
      enable = true;
      requirements =
        builtins.readFile "${inputs.pysci-core}/requirements-core.txt"
        + "\n"
        + builtins.readFile "${inputs.pysci-core}/requirements-linux.txt";
    };
  };

  env = {
    # Where native CUDA builds and nvcc resolve from. This is the Nix
    # cudatoolkit, distinct from the CUDA runtime torch bundles in its
    # own wheel.
    CUDA_HOME = "${pkgs.cudaPackages.cudatoolkit}";
    CUDA_PATH = "${pkgs.cudaPackages.cudatoolkit}";

    # Explicit runtime library path for the native deps above. devenv also
    # adds `packages` libraries to LD_LIBRARY_PATH, so this is belt and
    # suspenders, but it keeps the intent visible and self-documenting.
    LD_LIBRARY_PATH = lib.makeLibraryPath nativeLibs;
  };

  enterShell = ''
    echo "── pysci-ai devenv ──────────────────────────────────────────"
    python --version
    echo "venv:   ''${VIRTUAL_ENV:-<none>}"
    echo "python: $(command -v python)"
    if command -v nvidia-smi >/dev/null 2>&1; then
      nvidia-smi --query-gpu=name,driver_version,memory.total \
        --format=csv,noheader 2>&1 | sed 's/^/GPU:    /' || true
    else
      echo "GPU:    nvidia-smi not on PATH"
    fi
    echo "─────────────────────────────────────────────────────────────"
  '';
}
