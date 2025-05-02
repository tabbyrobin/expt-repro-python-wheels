#!/usr/bin/env bash
set -euo pipefail

# For building py-cryptography on an arbitrary debian system...

# sudo apt-get install -y build-essential python3-dev libssl-dev pkg-config

setupUv() {
  curl -LsSf https://astral.sh/uv/0.6.10/install.sh >install-uv.sh
  sh install-uv.sh
  source "$HOME/.local/bin/env"
}

installYq() {
  if [ ! -f /usr/bin/yq ]; then
    sudo wget https://github.com/mikefarah/yq/releases/download/v4.45.1/yq_linux_amd64 \
      -O /usr/bin/yq &&
      sudo chmod a+x /usr/bin/yq
  fi
}

# NOTE: we are installing rust within the docker image, not on the host.

setupRust() {
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs >rustup.sh
  # sudo here because act will run the actions as root ($HOME/.cargo/env => /root/.cargo/env)
  sh rustup.sh -y --profile minimal -c rustc,cargo
  # . "$HOME/.cargo/env"
  . "$CARGO_HOME/env"
}

# Should be done after setup uv and docker, as the nektos script will make bin/
# unwritable (unclear their rationale).
setupAct() {
  (
    cd "$HOME" || exit 1
    curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/nektos/act/master/install.sh >install-act.sh
    sudo bash install-act.sh v0.2.75
  )
  export PATH="$HOME/bin:$PATH"
}
