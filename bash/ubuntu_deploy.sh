#!/bin/bash

# Ubuntu 22.04 LTS 服务器初始化脚本

set -e

echo "=========================================="
echo "Ubuntu 22.04 LTS 服务器初始化脚本"
echo "=========================================="

# 0. 切换 APT 源到腾讯云镜像
echo "[0/12] 切换 APT 源到腾讯云镜像..."
# sudo cp -a /etc/apt/sources.list /etc/apt/sources.list.bak
# sudo sed -i "s@http://.*archive.ubuntu.com@http://mirrors.tencentyun.com@g" /etc/apt/sources.list
# sudo sed -i "s@http://.*security.ubuntu.com@http://mirrors.tencentyun.com@g" /etc/apt/sources.list

# 1. 更新包管理器
echo "[1/12] 更新包管理器..."
sudo apt-get update
sudo apt-get upgrade -y

# 2. 安装基础依赖工具
echo "[2/12] 安装基础依赖工具..."
sudo apt-get install -y ca-certificates curl wget gnupg lsb-release apt-transport-https

# 3. 安装 Docker (腾讯云镜像源)
echo "[3/12] 安装 Docker (腾讯云镜像源)..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://mirrors.cloud.tencent.com/docker-ce/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://mirrors.cloud.tencent.com/docker-ce/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER

# 3.1 配置 Docker 镜像加速源 (腾讯云内网)
echo "[3.1/12] 配置 Docker 镜像加速源..."
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "registry-mirrors": ["https://mirror.ccs.tencentyun.com"]
}
EOF
sudo systemctl restart docker

# 4. 安装 Java 21
echo "[4/12] 安装 Java 21..."
sudo apt-get install -y openjdk-21-jdk

# 设置 JAVA_HOME
echo 'export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64' >> ~/.bashrc
echo 'export PATH=$JAVA_HOME/bin:$PATH' >> ~/.bashrc

# 5. 安装 Python 3.10
echo "[5/12] 安装 Python 3.10..."
sudo apt-get install -y python3.10 python3.10-dev python3-pip
sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1

# 配置 pip 镜像 (内网)
echo "[5.1/12] 配置 pip 镜像..."
pip config set global.index-url http://mirrors.tencentyun.com/pypi/simple
pip config set global.trusted-host mirrors.tencentyun.com
python -m pip install --upgrade pip

# 6. 安装 gcc, g++, clang
echo "[6/12] 安装 gcc, g++, clang..."
sudo apt-get install -y gcc g++ clang

# 7. 安装 git
echo "[7/12] 安装 git..."
sudo apt-get install -y git

# 8. 安装 htop
echo "[8/12] 安装 htop..."
sudo apt-get install -y htop

# 9. 安装 Nginx
echo "[9/12] 安装 Nginx..."
sudo apt-get install -y nginx
sudo systemctl start nginx
sudo systemctl enable nginx

# 10. 安装 Node.js 20.x
echo "[10/12] 安装 Node.js 20.x..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
sudo apt-get install -y nodejs

# 启用 corepack (npm 版本管理)
echo "[10.1/12] 启用 corepack..."
sudo corepack enable

# 配置 npm 镜像 (内网)
echo "[10.2/12] 配置 npm 镜像..."
npm config set registry http://mirrors.tencentyun.com/npm/

# 配置 pnpm 镜像 (内网)
echo "[10.3/12] 配置 pnpm 镜像..."
corepack prepare pnpm@latest --activate
pnpm config set registry http://mirrors.tencentyun.com/npm/

# 配置 yarn 镜像 (内网)
echo "[10.4/12] 配置 yarn 镜像..."
COREPACK_ENABLE_DOWNLOAD_PROMPT=0 yarn config set registry http://mirrors.tencentyun.com/npm/

# 11. 安装其他常用工具
echo "[11/12] 安装其他常用工具..."
sudo apt-get install -y vim net-tools unzip zip tree ffmpeg

# 12. 安装 Rust
echo "[12/14] 安装 Rust..."
export RUSTUP_DIST_SERVER="https://rsproxy.cn"
export RUSTUP_UPDATE_ROOT="https://rsproxy.cn/rustup"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"

# 配置 Rust 镜像 (USTC)
echo "[12.1/14] 配置 Rust 镜像..."
mkdir -vp "${CARGO_HOME:-$HOME/.cargo}"
cat >> "${CARGO_HOME:-$HOME/.cargo}/config.toml" << 'EOF'
[source.crates-io]
replace-with = 'ustc'
[source.ustc]
registry = "sparse+https://mirrors.ustc.edu.cn/crates.io-index/"
[registries.ustc]
index = "sparse+https://mirrors.ustc.edu.cn/crates.io-index/"
EOF

# 13. 安装 Go 1.22
echo "[13/14] 安装 Go 1.22..."
GO_VERSION="1.22.0"
wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf /tmp/go.tar.gz
rm /tmp/go.tar.gz

# 设置 Go 环境变量
echo 'export PATH=/usr/local/go/bin:$PATH' >> ~/.bashrc
echo 'export GOPATH=$HOME/go' >> ~/.bashrc
echo 'export PATH=$GOPATH/bin:$PATH' >> ~/.bashrc

# 配置 Go 镜像 (腾讯云内网)
echo "[13.1/14] 配置 Go 镜像..."
mkdir -p ~/go
go env -w GOPROXY=http://mirrors.tencentyun.com/goproxy/,direct
go env -w GOSUMDB=off

# 14. 配置 Maven 镜像 (内网)
echo "[14/14] 配置 Maven 镜像..."
mkdir -p ~/.m2
cat > ~/.m2/settings.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0
                              http://maven.apache.org/xsd/settings-1.0.0.xsd">
  <mirrors>
    <mirror>
      <id>tencentyun</id>
      <name>Tencent Cloud Maven</name>
      <url>http://mirrors.tencentyun.com/nexus/repository/maven-public/</url>
      <mirrorOf>*</mirrorOf>
    </mirror>
  </mirrors>
</settings>
EOF

echo "=========================================="
echo "安装完成！"
echo "=========================================="
echo ""
echo "请注意："
echo "1. Docker 服务已启动并设为开机自启"
echo "2. Java 21 已安装，请重新登录终端以生效 JAVA_HOME"
echo "3. Python 3.10 已安装"
echo "4. 当前用户已加入 docker 组，请重新登录后生效"
echo "5. Go 已安装，请重新登录终端以生效 PATH"
echo ""
echo "验证安装："
echo "  docker --version"
echo "  docker compose version"
echo "  java -version"
echo "  python --version"
echo "  node --version"
echo "  npm --version"
echo "  gcc --version"
echo "  clang --version"
echo "  git --version"
echo "  htop"
echo "  nginx -v"
echo "  ffmpeg -version"
echo "  rustc --version"
echo "  cargo --version"
echo "  go version"
