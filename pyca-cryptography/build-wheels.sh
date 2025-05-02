#!/usr/bin/env bash
set -euo pipefail

. _setup_docker.sh
. _setup_etc.sh

setupAll() {
  setupDocker
  setupUv
  # uv tool install cibuildwheel
  uv tool install python-stripzip
  sudo apt-get install -qy debugedit
  installYq
}

getCsum() { sha256sum "$1" | cut -d' ' -f1; }

deterministicRust() {
  RUSTFLAGS="${RUSTFLAGS:-}"

  # https://git.jordan.im/arti/tree/doc/safer-build.md
  RUSTFLAGS="${RUSTFLAGS} --remap-path-prefix '$HOME/.cargo=.cargo' --remap-path-prefix '$(pwd)=.' --remap-path-prefix '$HOME=~'"
  # cargo build --locked --release -p arti

  # https://codeberg.org/stagex/stagex
  # RUSTFLAGS="${RUSTFLAGS} -C target-feature=+crt-static"

  {
    :
    # https://users.rust-lang.org/t/how-to-properly-use-remap-path-prefix/104406/6

    # "You can use CARGO_ENCODED_RUSTFLAGS instead which uses ASCII Unit
    # Separator (0x1f) instead of space as argument separator. You can also use
    # the new --config option to set the build.rustflags config to an array
    # formatted as toml.
    #
    # There is a cargo feature in the work to make this a lot easier."
  }

  # https://github.com/PyO3/maturin/issues/472
  # maturin build --cargo-extra-args="--locked"

  # http://rattler.build/latest/rebuild/

  # GH actions runner ubuntu-latest likely uses Rust 1.85.1, and Node.js
  # 20.19.0:
  # https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md
  # (Note however that pyca cryptography uses their own static node20.)

  # https://dev.to/gnunicorn/hunting-down-a-non-determinism-bug-in-our-rust-wasm-build-4fk1

  {
    # https://github.com/rust-lang/rust/issues/128675
    # https://nnethercote.github.io/perf-book/build-configuration.html
    # https://doc.rust-lang.org/nightly/rustc/codegen-options/

    RUSTFLAGS="${RUSTFLAGS} -C codegen-units=1 -C lto=off -C strip=debuginfo"
    # [profile.release]
    # codegen-units = 1
    # lto = true
    # # strip = true
    CARGO_INCREMENTAL=0 # 0 to disable
  }

  export CARGO_INCREMENTAL
  export RUSTFLAGS
}

# For stagex `make` commands to work, need to enable docker to use containerd:
# https://earthly.dev/blog/containerd-docker/

prepull() {
  sudo docker pull ghcr.io/pyca/cryptography-musllinux_1_2:x86_64
  sudo docker pull ghcr.io/pyca/cryptography-manylinux_2_34:x86_64
  sudo docker pull ghcr.io/pyca/cryptography-manylinux2014:x86_64
  sudo docker pull ghcr.io/pyca/cryptography-manylinux_2_28:x86_64
}

# For testing purposes, to speed things up, filter down the manylinux matrix to
# keep only: { NAME: "manylinux_2_34_x86_64", CONTAINER:
# "cryptography-manylinux_2_34:x86_64", RUNNER: "ubuntu-latest"}
#
# Tried to use act's `--matrix` option for this but could not get it to work for
# multilevel nested matrix elements... For example, not working:
#
# --matrix 'PYTHON:{ VERSION: "cp311-cp311", ABI_VERSION: "py39" }' \
#
# --matrix MANYLINUX.CONTAINER:cryptography-manylinux_2_34:x86_64 \
#
# So instead we are just doing a crude grep -v.
__filterMatrix() {
  (
    cd "$(dirname .github/workflows/wheel-builder.yml)" || exit 1
    cat wheel-builder.yml |
      grep -vE -- '- .*{.*NAME:.*RUNNER.*ubuntu-24\.04-arm' |
      grep -vE -- '- .*{.*NAME:.*(musllinux|manylinux2014|manylinux_2_28).*CONTAINER' |
      grep -vE -- '- .*{.*VERSION:.*(pypy|py37)' \
        >wheel-builder.yml.FILTERED
    mv wheel-builder.yml.FILTERED wheel-builder.yml
  )
  # TODO use yq to remove the manylinux `exclude:` block entirely.

  # yq -i '.a.b[0].c = "cool"' file.yaml
}

extractArtifacts() {
  local artifacts_dir="$1" wheelhouse_dir="$2"
  mkdir -p "${wheelhouse_dir}"
  find "${artifacts_dir}" -type f -name '*.zip' -print0 |
    xargs -0 -I {} sh -c "unzip {} -d '$wheelhouse_dir' && rm {}"
  [ 0 = "$(find "${artifacts_dir}" -type f | wc -l)" ] && rm -r "${artifacts_dir}"
}

runManylinuxJob() {
  local output_root="$1"

  rm -f event.json && printf '{ "ref": "%s" }' "$REPO_REF" >event.json

  {
    # shellcheck disable=SC2031
    time sudo -E -u "$USER" env "PATH=$PATH" \
      act \
      --input version="$VERSION" \
      --artifact-server-path "${output_root}/.artifacts" \
      --env ACTIONS_RUNTIME_TOKEN=foo \
      --env SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
      --env RUSTFLAGS="$RUSTFLAGS" \
      --env CARGO_INCREMENTAL="$CARGO_INCREMENTAL" \
      --env UV_CACHE_DIR="./MAGIC_uv_cache" \
      --eventpath event.json \
      -j manylinux \
      --container-options "-v /staticnodehost:/staticnodecontainer:rw,rshared -v /staticnodehost:/__e/node20:ro,rshared" \
      --platform ubuntu-latest=baserunner \
      --platform ubuntu-24.04-arm=baserunner \
      --pull=false

    # pull=false: Disable default forcePull. Needed for using a local image.
  } || true

  # We put `|| true` because we want to continue onwards and run further
  # commands even if the act command only partially succeeds.

  # --container-options "-v ~/myproj:/home/user/projects/myproj/"
  # https://github.com/nektos/act/issues/1548#issuecomment-1475036827

  # --platform ubuntu-latest=catthehacker/ubuntu:rust-latest
  # --platform ubuntu-latest=fwilhe2/act-runner:latest \
  # act default 'medium' image # catthehacker/ubuntu:act-latest
}

doPatching() {
  [ -f ../apply_diff ] && git apply ../crypto.diff && rm ../apply_diff

  #MOVED to the git clone step:
  # [ -f ../apply_checkout ] && git checkout "$REPO_REF" && rm ../apply_checkout

  # Newer versions of `action/checkout`(e.g. v4) are unsupported by act. TODO:
  # pin a specific commit.
  find .github -type f -print0 |
    xargs -0 sed -i 's#uses: actions/checkout.*$#uses: actions/checkout@v3#g'

  # NOTE: In addition, for certain invocations, we ALSO need to replace
  # `action/checkout` entirely, since it requires GITHUB_TOKEN if trying to pull
  # a specific ref. We'll replace it with git clone ... && git checkout ... This
  # is done by the patch/diff.

  __filterMatrix # FOR TESTING. TODO disable
}

postprocess() {
  # Examples:

  # /home/user/BLABLA/py-cryptography.git/tmpwheelhouse/.tmp25fNNV/cryptography-44.0.2/src/rust/cryptography-x509-verification/src/ops.rs

  # /home/user/BLABLA/py-cryptography.git/tmpwheelhouse/.tmp9ulE6J/cryptography-44.0.2/src/rust/cryptography-x509-verification/src/ops.rs

  :
  # TODO debugedit

  # TODO: stripzip
  # (
  #     cd ${output_root} || exit 1

  #     find "${output_root}/.artifacts" -type f

  # )
}

py_cryptography() {
  VERSION="${VERSION:-44.0.2}"
  REPO_REF=refs/tags/$VERSION
  PROJ_DIR=$(realpath py-cryptography.git)
  if [ ! -d "$PROJ_DIR" ]; then
    git clone https://github.com/pyca/cryptography "$PROJ_DIR"
    (cd "$PROJ_DIR" && git checkout "$REPO_REF")
  fi

  # export RUSTUP_HOME=$(realpath "$PROJ_DIR/.rustup/")
  # export CARGO_HOME=$(realpath "$PROJ_DIR/.cargo/")
  # echo ".... CARGO_HOME: $CARGO_HOME ...." >&2
  # setupRust
  # export PATH="$CARGO_HOME/bin/:$PATH"
  # printf 'PATH="%s/bin/:$PATH"' "$CARGO_HOME" >>.env

  # https://github.com/nektos/act/issues/2290
  # https://github.com/nektos/act/issues/678#issuecomment-1693751996

  # time prepull
  setupAct
  # shellcheck disable=SC2031
  time sudo -E -u "$USER" env "PATH=$PATH" docker build -t baserunner .

  script_dir=$(pwd) && export script_dir

  # local output_root
  output_root=$(realpath "$PWD")
  export output_root

  (
    cd "$PROJ_DIR" || exit 1

    # doPatching
    cp "${script_dir}/files/wheel-builder.yml" .github/workflows/wheel-builder.yml

    act -l

    deterministicRust
    SOURCE_DATE_EPOCH=$(git log -1 --pretty=%ct) && export SOURCE_DATE_EPOCH

    runManylinuxJob "${output_root}"

    extractArtifacts "${output_root}/.artifacts" "${output_root}/wheelhouse"
    # TODO postprocess
  )

  mv "${output_root}/wheelhouse" "$(date -Iseconds).wheelhouse"
}

# buildIt(){
# set -e

# OPENSSL_VERSION="3.0.16"
# CWD=$(pwd)

# uv tool install virtualenv
# virtualenv env
# . env/bin/activate
# pip install -U setuptools
# pip install -U wheel pip
# wget https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz
# #curl -O https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
# tar xvf openssl-${OPENSSL_VERSION}.tar.gz
# cd openssl-${OPENSSL_VERSION}
# ./config no-shared no-ssl2 no-ssl3 -fPIC --prefix=${CWD}/openssl
# make && make install
# cd ..
# OPENSSL_DIR="${CWD}/openssl" pip wheel --no-cache-dir --no-binary cryptography cryptography
# }

# py_cryptography() {
# 	# https://cryptography.io/en/latest/installation/#building-cryptography-on-linux
# 	#setupAll

# 	#sudo apt-get install build-essential libssl-dev libffi-dev python3-dev pkg-config

# 	export CIBW_BEFORE_ALL="cat /etc/os-release; curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs >rustup.sh && sh rustup.sh -y --profile minimal -c rustc,cargo && yum -y install redhat-rpm-config gcc libffi-devel python3-devel openssl-devel"
#         export CIBW_ENVIRONMENT_LINUX='PATH=$HOME/.cargo/bin:$PATH'

# 	# pip install cryptography --no-binary cryptography

# 	buildWheels
# # TODO: for now this is failing to build because CentOS 7 (which was chosen automatically by cibuildwheel for the build id i specified)
# # has openSSL which is too old. Must find a binary distribution of openssl of the appropriate version.
# # (Error: cargo:warning=/project/target/release/build/cryptography-cffi-0b7789797da856ba/out/_openssl.c:1325:6: error: #error "pyca/cryptography MUST be linked with Openssl 1.1.1e or later")

# }

setupAll
py_cryptography

# local f
# f=cryptography-44.0.2-cp39-abi3-manylinux_2_34_x86_64.whl
