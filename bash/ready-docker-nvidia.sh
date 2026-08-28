#!/bin/bash

# Ntkskwk@github
# 2024/04/07

set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

# 检查当前用户是否有root权限
if [ "$(id -u)" != "0" ]; then
    echo "错误：请以root权限运行此脚本！"
    exit 1
fi

# NVIDIA Container Toolkit 只负责把宿主机驱动注入容器，不负责安装驱动。
if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo "错误：未检测到 nvidia-smi，请先在宿主机安装 NVIDIA 驱动。"
    exit 1
fi
nvidia-smi >/dev/null

if [ ! -r /etc/os-release ]; then
    echo "错误：无法读取 /etc/os-release。"
    exit 1
fi
. /etc/os-release
if [ "${ID:-}" != "ubuntu" ]; then
    echo "错误：此脚本当前只支持 Ubuntu，当前系统为 ${ID:-unknown}。"
    exit 1
fi

apt-get update
apt-get install -y ca-certificates curl gnupg

# https://docs.docker.com/engine/install/ubuntu/
# 移除Ubuntu源或其他来源中可能与Docker CE冲突的包。
apt-get remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
docker run hello-world

# https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
install -m 0755 -d /usr/share/keyrings
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

apt-get update
apt-get install -y nvidia-container-toolkit

nvidia-ctk runtime configure --runtime=docker
systemctl daemon-reload
systemctl restart docker

docker run --rm --gpus all ubuntu nvidia-smi
docker compose version
