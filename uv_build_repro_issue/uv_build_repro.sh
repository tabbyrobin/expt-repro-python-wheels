#!/usr/bin/env bash
# Script is a minimal example to show that `uv build` command produces
# non-reproducible builds because it uses non-deterministic temp dir paths. For
# the same project, building with `uv venv` + `maturin build` produces a
# bit-for-bit reproducible build.
#
# Script tested on debian 12.
#
# NOTE: There are also comments and code in this file about building from sdist
# (vs git), but as concerns just *reproducibility*, you can ignore anything
# about sdists and just focus on the builds from git.

# shellcheck disable=SC1091

set -euo pipefail

setupUv() {
  # e.g. 0.6.10 or 0.6.14
  curl -LsSf https://astral.sh/uv/0.6.14/install.sh >install-uv.sh
  sh install-uv.sh
  source "$HOME/.local/bin/env"
}

setup() {
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get install -qqy curl git unzip

  setupUv

  sudo apt-get install -qy build-essential python3-dev libssl-dev pkg-config # patchelf

  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs >rustup.sh
  sh rustup.sh -y --profile minimal -c cargo --default-toolchain=1.86.0
  . "$HOME/.cargo/env"
}

setupProjWithGit() {
  [ -d "$PROJ_DIR" ] || git clone https://github.com/pyca/cryptography "$PROJ_DIR"
  (cd "$PROJ_DIR" && git checkout refs/tags/44.0.2)
}

getCsum() { sha256sum "$1" | cut -d' ' -f1; }
extractFromTarball() {
  [ -f "$ARCHIVE_PATH" ] || curl "${ARCHIVE_URL}" >"$ARCHIVE_PATH"
  [ "_$(getCsum "$ARCHIVE_PATH")" == "_${ARCHIVE_CSUM}" ] || exit 1
  if [ ! -d "$PROJ_DIR" ]; then
    { mkdir -p "$PROJ_DIR" && tar xzf "$ARCHIVE_PATH" -C "$PROJ_DIR" --strip-components=1; }
  fi
}

setupProjWithSDist() {
  REQS_URL=https://raw.githubusercontent.com/pyca/cryptography/refs/tags/44.0.2/.github/requirements/build-requirements.txt

  ARCHIVE_PATH=cryptography-44.0.2.tar.gz
  ARCHIVE_URL=https://files.pythonhosted.org/packages/cd/25/4ce80c78963834b8a9fd1cc1266be5ed8d1840785c0f2e1b73b8d128d505/cryptography-44.0.2.tar.gz
  ARCHIVE_CSUM=c63454aa261a0cf0c5b4718349629793e9e634993538db841165b3df74f37ec0
  extractFromTarball

  (
    cd "$PROJ_DIR"

    # This mimics the behavior of PyCA cryptography's GitHub actions yaml (in
    # wheel-builder.yml), which builds an sdist and then additionally does
    # checkout of just `.github/requirements/build-requirements.txt` for the
    # wheel build. Of course, the GHA workflow builds its own sdist from repo
    # each time; it does not download from pythonhosted.org.

    reqs_path=.github/requirements/build-requirements.txt
    mkdir -p "$(dirname "$reqs_path")"
    curl "$REQS_URL" >"$reqs_path"
  )
}

showDigest() {
  (
    cd tmpwheelhouse

    unzip -qq -- *.whl
    files=$(find . -name '*.so*' | sort)

    echo ========================================
    sha256sum -- *.whl
    du -- *.whl

    for f in $files; do
      echo ====
      sha256sum "$f"
      echo ====
      { strings --all --bytes=8 "$f" | grep '\/src\/.*\.rs' | head -n 15; } || true
      echo ====
      { strings --all --bytes=8 "$f" | grep '\.tmp' | head -n 15; } || true
    done

    echo ========================================
  )
  mv tmpwheelhouse "../${PROJ_DIR}.tmpwheelhouse.$(date -Iseconds)"
}

resetProjDir() {
  rm -rf "$PROJ_DIR"
  cp -r "$STAGING_PROJ_DIR" "$PROJ_DIR"
  # git clean -d -x -f &&
}

# Not Reproducible!
uvBuildDefault() {
  resetProjDir
  (
    cd "$PROJ_DIR"

    # NOTE: This runs if building from git, but not from an extracted sdist.

    uv build \
      --require-hashes --build-constraints=.github/requirements/build-requirements.txt \
      -o tmpwheelhouse \
      --python "python3.11"

    showDigest
  )

  # Error when building from sdist:

  # 💥 maturin failed Caused by: Failed to build source distribution Caused by:
  #   Failed to query file list from git: exit status: 128 --- Project Path:
  #   /opt/OUTPUT/cryptography.sdist.dir.__uvBuildDefault__ --- Stdout: --- Stderr:
  #   fatal: not a git repository (or any parent up to mount point /opt) Stopping at
  #   filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set). Error: command
  #   ['maturin', 'pep517', 'write-sdist', '--sdist-directory',
  #   '/opt/OUTPUT/cryptography.sdist.dir.__uvBuildDefault__/tmpwheelhouse'] retur
  #   ned non-zero exit status 1

  # TODO: Determine whether this is intended behavior. It appears that `maturin
  # pep517 write-sdist ...` command only works with a git repository (and not,
  # for example, from a git archive).
}

# Reproducible in this script, but not as part of the GHA yaml?
uvBuildWheel() {
  resetProjDir
  (
    cd "$PROJ_DIR"

    # Works to build from both: git or extracted sdist.

    uv build --wheel \
      --require-hashes --build-constraints=.github/requirements/build-requirements.txt \
      -o tmpwheelhouse \
      --python "python3.11"

    showDigest
  )
}

# Reproducible.
uvVenvMaturinBuild() {
  resetProjDir
  (
    cd "$PROJ_DIR"

    # Works to build from both: git or extracted sdist.

    uv venv --relocatable
    uv pip install maturin[patchelf]
    uv pip install --require-hashes -r .github/requirements/build-requirements.txt

    uv run maturin build --interpreter "python3.11" -o tmpwheelhouse
    # uv run maturin build --interpreter "$(uv run which python)" -o tmpwheelhouse

    # Explanation: `--interpreter <PYTHON>` apparently triggers maturin to build
    # only a wheel, rather than doing an sdist->wheel PEP 517 build? This does
    # not appear to really be documented as such, but refer to these links:
    # https://github.com/PyO3/maturin/issues/197
    # https://github.com/pyca/cryptography/blob/56cfce682c8bd2ee5101b654a429b05d0f610f0e/.github/workflows/wheel-builder.yml#L146
    #
    # In `uv build`, the `--python` option is seemingly equivalent to maturin's
    # `--interpreter`.

    # NOTE: This one runs if building from git, but not from an extracted sdist:
    # `uv run maturin build -o tmpwheelhouse`

    showDigest
  )
}

_runTwice() {
  local fn="$1"
  for i in 1 2; do
    printf '\n\n%s\n\n' "### Running: ${fn} ... ${i}/2 ###"
    PROJ_DIR="${PROJ_DIR}.__${fn}__" ${fn}
  done
}


_doGit() {
  export PROJ_DIR=cryptography.git
  export STAGING_PROJ_DIR="_STAGING_.${PROJ_DIR}"

  {
    printf '\n\n%s\n\n' "## Running from git repo ##"
    PROJ_DIR="${STAGING_PROJ_DIR}" setupProjWithGit

    _runTwice uvBuildDefault
    _runTwice uvBuildWheel
    _runTwice uvVenvMaturinBuild

  } 2> >(tee "${PROJ_DIR}.STDERR.log" >&2) | tee "${PROJ_DIR}.STDOUT.log"
}

_doSDist() {
  export PROJ_DIR=cryptography.sdist.dir
  export STAGING_PROJ_DIR="_STAGING_.${PROJ_DIR}"

  {
    printf '\n\n%s\n\n' "## Running from sdist ##"
    PROJ_DIR="${STAGING_PROJ_DIR}" setupProjWithSDist

    _runTwice uvBuildDefault
    _runTwice uvBuildWheel
    _runTwice uvVenvMaturinBuild

  } 2> >(tee "${PROJ_DIR}.STDERR.log" >&2) | tee "${PROJ_DIR}.STDOUT.log"
}

doUvBuildRepro() {
  setup
  export CARGO_TERM_QUIET=true
  export UV_CACHE_DIR=.cache
  export OPENSSL_STATIC=1
  _doGit
  # _doSDist
}

time doUvBuildRepro

# Display an overview of the checksums
grep -E '(_rust\.abi3\.so|##)' ./*.STDOUT.log
