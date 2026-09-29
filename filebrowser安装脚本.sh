#!/usr/bin/env bash
# =============================================================
# File Browser 一键安装脚本（Ubuntu 26.04 LTS / resolute）
# 作用：安装 Docker CE → 添加当前用户到 docker 组 → 拉取 File Browser 镜像
# 用法：bash filebrowser安装脚本.sh
# =============================================================
set -euo pipefail

echo "==> [1/4] 更新软件源并安装依赖"
sudo apt update
sudo apt install -y ca-certificates curl gnupg

echo "==> [2/4] 配置 Docker 官方 APT 仓库（自动识别代号 resolute）"
sudo install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.asc ]; then
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
fi

CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update

# 若官方仓库暂无 resolute 索引导致失败，自动回退到 noble（24.04，二进制兼容）
if ! apt-cache policy docker-ce 2>/dev/null | grep -q "Candidate: [0-9]"; then
  echo "!! 官方仓库暂未提供 ${CODENAME} 索引，回退使用 noble 仓库"
  sudo sed -i "s/Suites: .*/Suites: noble/" /etc/apt/sources.list.d/docker.sources
  sudo apt update
fi

echo "==> [3/4] 安装 Docker CE"
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 只本次启动，不开机自启。
# 注意：docker.socket 的“套接字激活”也会拉起 docker，必须一并禁用；
# 之后每次由启动脚本按需 systemctl start docker。
sudo systemctl start docker
sudo systemctl disable docker.service docker.socket containerd.service >/dev/null 2>&1 || true

echo "==> [4/4] 将当前用户加入 docker 组（免 sudo 使用 docker）"
sudo usermod -aG docker "$USER"

echo "==> 拉取 File Browser 镜像"
sudo docker pull filebrowser/filebrowser:latest

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
  read -rs -p "请输入密码（不可为空，输入时不显示）：" FB_PASS
  echo ""
  if [ -z "$FB_PASS" ]; then
    echo "!! 密码不能为空，请重新输入"
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
echo " 共享目录："
for s in "${FB_SHARES[@]}"; do echo "   · $s"; done
echo ""
echo " 注意：docker 组权限需要新会话才能生效（26.04 默认无 newgrp 命令）。"
echo " 请执行： su - \$USER   （输入登录密码，当前终端立即生效）"
echo "         或者直接注销系统重新登录。"
echo " 然后运行： bash filebrowser启动脚本.sh"
echo "============================================================"
