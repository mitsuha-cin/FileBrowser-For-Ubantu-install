#!/usr/bin/env bash
# =============================================================
# File Browser 极简安装脚本（docker.io 版，备用方案）
# 适用：官方 Docker CE 仓库安装失败 / 想用 Ubuntu 自带源快速装
# 区别：用 Ubuntu 仓库的 docker.io，无需配置第三方仓库
# 用法：bash filebrowser安装脚本-极简版.sh
# =============================================================
set -euo pipefail

echo "==> [1/3] 安装 docker.io（Ubuntu 官方仓库）"
sudo apt update
sudo apt install -y docker.io curl

# 只本次启动，不开机自启（socket 激活一并禁用）
sudo systemctl start docker
sudo systemctl disable docker.service docker.socket containerd.service >/dev/null 2>&1 || true

echo "==> [2/3] 将当前用户加入 docker 组（免 sudo 使用 docker）"
sudo usermod -aG docker "$USER"

echo "==> [3/3] 拉取 File Browser 与 WebDAV 镜像"
sudo docker pull filebrowser/filebrowser:latest
sudo docker pull sigoden/dufs:latest

# 创建数据目录与数据库文件
mkdir -p "$HOME/Videos" "$HOME/.filebrowser"
touch "$HOME/.filebrowser/filebrowser.db"

# ---------- 初始配置（1/2）：登录账号 ----------
echo ""
echo "============================================================"
echo " 初始配置（1/2）：设置 File Browser 登录账号"
echo "============================================================"
FB_USER=""
while [ -z "$FB_USER" ]; do
  read -r -p "请输入用户名（直接回车使用 admin）：" FB_USER
  FB_USER="${FB_USER:-admin}"
done

while true; do
  read -rs -p "请输入密码（至少 12 位，输入时不显示）：" FB_PASS
  echo ""
  if [ ${#FB_PASS} -lt 12 ]; then
    echo "!! 密码不足 12 位（File Browser 的硬性要求），请重新输入"
    continue
  fi
  read -rs -p "请再次输入密码确认：" FB_PASS2
  echo ""
  if [ "$FB_PASS" = "$FB_PASS2" ]; then
    break
  fi
  echo "!! 两次输入不一致，请重新输入"
done

# ---------- 初始配置（2/2）：共享目录（可添加多个） ----------
echo ""
echo "============================================================"
echo " 初始配置（2/2）：配置共享目录（可添加多个）"
echo " 手机端会看到每个目录最后一级的名字，如 电影、图片"
echo "============================================================"
FB_SHARES=()
first=1
while true; do
  if [ "$first" -eq 1 ]; then
    read -r -p "请输入共享目录路径（直接回车使用默认 ~/Videos）：" p
    p="${p:-$HOME/Videos}"
    first=0
  else
    read -r -p "再添加一个？输入路径，或直接回车结束：" p
    [ -z "$p" ] && break
  fi
  p="${p/#\~/$HOME}"      # 支持 ~ 开头
  p="${p%/}"              # 去掉结尾斜杠
  if [ ! -d "$p" ]; then
    read -r -p "目录 $p 不存在，是否创建？[y/N]：" mk
    case "$mk" in
      y|Y) mkdir -p "$p" ;;
      *)   echo "    已跳过该目录"; continue ;;
    esac
  fi
  FB_SHARES+=("$p")
  echo "    已添加：$p"
done

# 写入配置文件（仅本人可读）
CONF="$HOME/.filebrowser/install.conf"
{
  printf 'FB_USER=%q\n' "$FB_USER"
  printf 'FB_PASS=%q\n' "$FB_PASS"
  echo "FB_SHARES=("
  for s in "${FB_SHARES[@]}"; do printf '  %q\n' "$s"; done
  echo ")"
} > "$CONF"
chmod 600 "$CONF"

echo ""
echo "============================================================"
echo " 安装完成！配置已保存到 ~/.filebrowser/install.conf"
echo ""
echo " 登录账号： $FB_USER（密码为你刚才设置的）"
echo ""
echo " 共享目录（左边 = 手机端看到的文件夹名，右边 = 实际路径）："
declare -A SEEN_NAMES=()
for s in "${FB_SHARES[@]}"; do
  base="$(basename "$s")"; name="$base"; n=2
  while [ -n "${SEEN_NAMES[$name]:-}" ]; do name="${base}_${n}"; n=$((n + 1)); done
  SEEN_NAMES[$name]=1
  echo "   · $name  ←  $s"
done
echo ""
echo " 想共享 DATA 盘里的某个文件夹，路径要写到那一级，例如："
echo "   /run/media/cince/DATA/UU精选  → 手机端显示 UU精选"
echo "   只写 /run/media/cince/DATA   → 手机端显示 DATA（整盘共享）"
echo ""
echo " 之后想改：nano ~/.filebrowser/install.conf，重启启动脚本即生效。"
echo ""
echo " 注意：docker 组权限需要新会话才能生效（26.04 默认无 newgrp 命令）。"
echo " 请执行： su - \$USER   （输入登录密码，当前终端立即生效）"
echo "         或者直接注销系统重新登录。"
echo " 然后运行： bash filebrowser启动脚本.sh"
echo "============================================================"
