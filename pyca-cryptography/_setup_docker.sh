#!/usr/bin/env bash
set -euo pipefail

dockerRootDirSetup() {
  local DOCKER_ROOT_DIR="$1"
  sudo mkdir -p "$DOCKER_ROOT_DIR"

  # echo "Running chown -R on $DOCKER_ROOT_DIR -- may take a while..." >&2
  # sudo chown -R root:root "$DOCKER_ROOT_DIR"
  # sudo chmod -R 700 "$DOCKER_ROOT_DIR"

  sudo chown root:root "$DOCKER_ROOT_DIR"
  sudo chmod 700 "$DOCKER_ROOT_DIR"

  printf '{ "data-root": "%s" }\n' "$DOCKER_ROOT_DIR" |
    sudo cp /dev/stdin /etc/docker/daemon.json

  # https://diditho.com/2025/01/17/where-docker-stores-images-on-debian-12-and-how-to-customize-the-storage-directory/
}

# TODO: setup docker for multiarch emulation as described here:
# https://www.stereolabs.com/docs/docker/building-arm-container-on-x86

# NOTE: we appear to need rootful Docker for this workflow. Using rootless
# Docker gave errors about `/staticnodehost` directory.
setupDocker() {
  export DEBIAN_FRONTEND=noninteractive
  for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove -qqy $pkg; done

  sudo apt-get install -y dbus-user-session slirp4netns uidmap ||
    sudo dnf install -y fuse-overlayfs iptables shadow-utils

  sudo apt-get install -qy ca-certificates curl gnupg lsb-release dirmngr software-properties-common apt-transport-https

  curl -fsSL https://get.docker.com -o install-docker.sh
  # Faster re-runs (it's idempotent enough for our needs)
  sed -i 's/sleep 20/sleep 1/g' install-docker.sh
  # 25.0 is somewhat LTS (as of 2025-04): https://endoflife.date/docker-engine
  sudo sh install-docker.sh --version 25.0

  export PATH="$HOME/bin:$PATH"

  # https://docs.docker.com/engine/install/linux-postinstall/

  sudo groupadd -f docker
  sudo usermod -aG docker "$USER"

  mkdir -p /home/"$USER"/.docker &&
    {
      sudo chown "$USER":"$USER" /home/"$USER"/.docker -R
      sudo chmod g+rwx "$HOME/.docker" -R
    }

  dockerRootDirSetup "$HOME/docker-data"

  sudo systemctl restart docker
  sudo systemctl restart containerd

  # https://superuser.com/questions/272061/reload-a-linux-users-group-assignments-without-logging-out
  # newgrp docker
  # newgrp -
  # exec sudo -s -u ${USER}
  # exec sudo -E -u "$USER" "$SHELL"
  # exec sg docker "newgrp $(id -gn)"

  # docker run hello-world
}
