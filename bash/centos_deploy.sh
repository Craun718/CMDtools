#!/bin/bash

# CentOS 7.7 服务器初始化脚本

set -e

echo "=========================================="
echo "CentOS 7.7 服务器初始化脚本"
echo "=========================================="

# 0. 切换 YUM 源 (CentOS 7 已停止维护，切换到腾讯云镜像源)
echo "[0/12] 切换 YUM 源到腾讯云镜像..."
sudo curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.tencent.com/repo/centos7_base.repo
sudo curl -o /etc/yum.repos.d/CentOS-Epel.repo https://mirrors.tencent.com/repo/epel7.repo

# 1. 更新包管理器
echo "[1/12] 更新包管理器..."
sudo yum check-update || true
sudo yum update -y

# 2. 安装基础依赖工具
echo "[2/12] 安装基础依赖工具..."
sudo yum install -y yum-utils curl wget

# 3. 安装 Docker (腾讯云镜像源)
echo "[3/12] 安装 Docker (腾讯云镜像源)..."
sudo yum-config-manager --add-repo https://mirrors.cloud.tencent.com/docker-ce/linux/centos/docker-ce.repo
sudo sed -i "s/download.docker.com/mirrors.tencentyun.com\/docker-ce/g" /etc/yum.repos.d/docker-ce.repo
sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER

# 4. 安装 Java 21
echo "[4/12] 安装 Java 21..."
sudo yum install -y java-21-openjdk java-21-openjdk-devel

# 设置 JAVA_HOME
echo 'export JAVA_HOME=/usr/lib/jvm/java-21-openjdk' >> ~/.bashrc
echo 'export PATH=$JAVA_HOME/bin:$PATH' >> ~/.bashrc

# 5. 安装 Python 3.10 (通过 SCL)
echo "[5/12] 安装 Python 3.10..."
sudo yum install -y epel-release
sudo yum install -y centos-release-scl
sudo yum install -y python310 python310-devel python310-pip
sudo ln -sf /opt/rh/python310/root/bin/python /usr/bin/python
sudo ln -sf /opt/rh/python310/root/bin/python /usr/bin/python3
sudo ln -sf /opt/rh/python310/root/bin/pip /usr/bin/pip
sudo ln -sf /opt/rh/python310/root/bin/pip /usr/bin/pip3

# 配置 pip 镜像 (内网)
echo "[5.1/13] 配置 pip 镜像..."
pip config set global.index-url http://mirrors.tencentyun.com/pypi/simple
pip config set global.trusted-host mirrors.tencentyun.com
python -m pip install --upgrade pip

# 6. 安装 gcc, g++, clang
echo "[6/14] 安装 gcc, g++, clang..."
sudo yum install -y gcc gcc-c++ clang

# 7. 安装 git
echo "[7/14] 安装 git..."
sudo yum install -y git

# 8. 安装 htop
echo "[8/14] 安装 htop..."
sudo yum install -y htop

# 9. 安装 Nginx
echo "[9/14] 安装 Nginx..."
sudo yum install -y nginx
sudo systemctl start nginx
sudo systemctl enable nginx

# 10. 安装 Node.js 20.x
echo "[10/14] 安装 Node.js 20.x..."
curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
sudo yum install -y nodejs

# 启用 corepack (npm 版本管理)
echo "[10.1/14] 启用 corepack..."
sudo corepack enable

# 配置 npm 镜像 (内网)
echo "[10.2/14] 配置 npm 镜像..."
npm config set registry http://mirrors.tencentyun.com/npm/

# 配置 pnpm 镜像 (内网)
echo "[10.3/14] 配置 pnpm 镜像..."
corepack prepare pnpm@latest --activate
pnpm config set registry http://mirrors.tencentyun.com/npm/

# 配置 yarn 镜像 (内网)
echo "[10.4/14] 配置 yarn 镜像..."
COREPACK_ENABLE_DOWNLOAD_PROMPT=0 yarn config set registry http://mirrors.tencentyun.com/npm/

# 11. 安装其他常用工具
echo "[11/14] 安装其他常用工具..."
sudo yum install -y vim net-tools unzip zip tree

# 12. 安装 FFmpeg (需要 RPMFusion 源)
echo "[12/13] 安装 FFmpeg..."
sudo yum install -y https://download1.rpmfusion.org/free/el/rpmfusion-free-release-7.noarch.rpm
sudo yum install -y ffmpeg

# 13. 安装 Rust
echo "[13/15] 安装 Rust..."
export RUSTUP_DIST_SERVER="https://rsproxy.cn"
export RUSTUP_UPDATE_ROOT="https://rsproxy.cn/rustup"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"

# 配置 Rust 镜像 (USTC)
echo "[13.1/15] 配置 Rust 镜像..."
mkdir -vp "${CARGO_HOME:-$HOME/.cargo}"
cat >> "${CARGO_HOME:-$HOME/.cargo}/config.toml" << 'EOF'
[source.crates-io]
replace-with = 'ustc'
[source.ustc]
registry = "sparse+https://mirrors.ustc.edu.cn/crates.io-index/"
[registries.ustc]
index = "sparse+https://mirrors.ustc.edu.cn/crates.io-index/"
EOF

# 14. 配置 Maven 镜像 (内网)
echo "[14/15] 配置 Maven 镜像..."
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
echo "3. Python 3.10 已安装 (通过 SCL)"
echo "4. 当前用户已加入 docker 组，请重新登录后生效"
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
