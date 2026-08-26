#!/bin/bash
# Vim 基础配置一键部署脚本
# 用法: bash setup_vim.sh

set -e

VIMRC="$HOME/.vimrc"
BACKUP_SUFFIX=".bak.$(date +%Y%m%d_%H%M%S)"

# 打印带颜色的提示
print_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

print_warn() {
    echo -e "\033[33m[WARN]\033[0m $1"
}

# 1. 检查是否存在旧配置，并自动备份
if [ -f "$VIMRC" ] || [ -L "$VIMRC" ]; then
    print_warn "检测到已存在配置文件: $VIMRC"
    BACKUP_PATH="${VIMRC}${BACKUP_SUFFIX}"
    mv "$VIMRC" "$BACKUP_PATH"
    print_info "已备份原配置到: $BACKUP_PATH"
fi

# 2. 写入新配置
cat > "$VIMRC" << 'EOF'
" ============================================
" 基础 Vim 配置 (适合绝大多数开发场景)
" ============================================

" ---------- 界面显示 ----------
set number              " 显示行号
syntax on               " 开启语法高亮
set cursorline          " 高亮当前行
set showmatch           " 高亮匹配括号

" ---------- 缩进与空格 ----------
set tabstop=4           " Tab 宽度 4 空格
set shiftwidth=4        " 自动缩进宽度 4 空格
set expandtab           " 将 Tab 转为空格

" ---------- 搜索优化 ----------
set incsearch           " 增量搜索
set hlsearch            " 高亮所有搜索结果
set ignorecase          " 搜索忽略大小写
set smartcase           " 若含大写则自动大小写敏感

" ---------- 其他实用 ----------
set nocompatible        " 关闭 Vi 兼容模式 (必需)
set mouse=a             " 启用鼠标支持 (终端可用)
set encoding=utf-8      " 统一文件编码
set fileencodings=utf-8,gbk,gb2312,cp936 " 支持中文编码
EOF

print_info "新配置文件已写入: $VIMRC"

# 3. 检查 Vim 版本并尝试加载
if command -v vim &> /dev/null; then
    print_info "Vim 已安装，版本信息:"
    vim --version | head -n 1
else
    print_warn "未检测到 Vim 命令，请先安装 Vim (如: apt install vim / yum install vim)"
fi

# 4. 尝试立即生效 (给当前终端)
if [ -n "$VIM" ]; then
    # 如果是在 Vim 内部执行，提醒 source
    print_info "若当前已在 Vim 中，可执行 :source $VIMRC 立即生效"
else
    print_info "新配置将在下次打开 Vim 时生效"
fi

print_info "✅ 脚本执行完毕！"
