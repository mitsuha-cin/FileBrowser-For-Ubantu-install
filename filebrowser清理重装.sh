#!/usr/bin/env bash
# =============================================================
# File Browser / Docker 彻底清理 + 重装脚本
#
# 作用：
#   1. 自动检测本机安装过的所有 Docker 相关软件包
#      （apt 版 docker.io / docker-ce / docker-engine / containerd / runc，
#        以及 snap 版 docker）
#   2. 停止并删除所有容器、镜像、卷，清空 /var/lib/docker 等数据目录
#      —— 包括 jellyfin、open-webui、immich 在内，全部删除，不可恢复
#   3. 清理 Docker APT 仓库、GPG 密钥、File Browser 配置
#   4. 清理完成后可选择立即重装（CE 正式版 / docker.io 极简版）
#
# 不会动的内容：
#   - ~/Videos（你的视频文件原样保留）
#   - 其他与 Docker 无关的软件
#
# 用法：bash filebrowser清理重装.sh
# =============================================================
set -uo pipefail

echo "============================================================"
echo " ⚠️  警 告：这是【彻底清空】操作"
echo "============================================================"
echo " 以下内容将被永久删除，不可恢复："
echo "   · 所有 Docker 容器、镜像、数据卷（含 jellyfin / immich 等）"
echo "   · /var/lib/docker、/var/lib/containerd 全部数据"
echo "   · 所有 Docker 相关软件包（自动检测）"
echo "   · Docker APT 仓库配置与密钥"
echo "   · File Browser 账号数据库与配置（~/.filebrowser，含 filebrowser.db，密码会重置）"
echo ""
echo " 不会删除：~/Videos 里的视频文件"
echo "============================================================"
read -r -p "确认继续？请输入大写 YES 开始清理：" confirm
if [ "$confirm" != "YES" ]; then
  echo "已取消，未做任何修改。"
  exit 0
fi

# ---------- 1. 检测已安装的 Docker 相关包 ----------
echo ""
echo "==> [1/6] 检测本机已安装的 Docker 相关软件包 ..."
APT_PKGS="$(dpkg -l 2>/dev/null | awk '/^ii|^rc/ {print $2}' | grep -E '^(docker\.io|docker-ce|docker-ce-cli|docker-ce-rootless-extras|docker-engine|docker-buildx-plugin|docker-compose-plugin|docker-compose|containerd\.io|containerd|runc)$' || true)"

SNAP_DOCKER=""
if command -v snap >/dev/null 2>&1 && snap list docker >/dev/null 2>&1; then
  SNAP_DOCKER="docker"
fi

if [ -z "$APT_PKGS" ] && [ -z "$SNAP_DOCKER" ]; then
  echo "    未检测到任何 Docker 软件包（可能本来就是干净的）"
else
  echo "    检测到以下软件包，将全部卸载："
  [ -n "$APT_PKGS" ] && echo "$APT_PKGS" | sed 's/^/      [apt]  /'
  [ -n "$SNAP_DOCKER" ] && echo "      [snap] docker"
fi

# ---------- 2. 停止一切 ----------
echo ""
echo "==> [2/6] 停止所有容器与 Docker 服务 ..."
if command -v docker >/dev/null 2>&1; then
  # 显式清理本项目的两个容器
  docker rm -f filebrowser filebrowser-webdav >/dev/null 2>&1 || true
  docker stop $(docker ps -aq 2>/dev/null) >/dev/null 2>&1 || true
fi
sudo systemctl stop docker.service docker.socket containerd.service >/dev/null 2>&1 || true

# ---------- 3. 卸载软件包 ----------
echo ""
echo "==> [3/6] 卸载软件包 ..."
if [ -n "$SNAP_DOCKER" ]; then
  sudo snap remove --purge docker || true
fi
if [ -n "$APT_PKGS" ]; then
  # shellcheck disable=SC2086
  sudo apt purge -y $APT_PKGS
fi
sudo apt autoremove -y --purge

# ---------- 4. 删除数据与配置 ----------
echo ""
echo "==> [4/6] 删除数据目录与仓库配置 ..."
sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker
sudo rm -f  /var/run/docker.sock /var/run/docker.pid
sudo rm -f  /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/docker.sources
sudo rm -f  /etc/apt/keyrings/docker.asc /etc/apt/keyrings/docker.gpg
sudo rm -f  /usr/share/keyrings/docker-archive-keyring.gpg

# File Browser 账号数据库与配置（含异常状态遗留的库文件，重装后从零初始化）
echo "    删除 File Browser 账号数据库：~/.filebrowser/filebrowser.db"
rm -f "$HOME/.filebrowser/filebrowser.db"
echo "    删除 File Browser 全部配置：~/.filebrowser（含 install.conf）"
rm -rf "$HOME/.filebrowser" "$HOME/.docker"
sudo groupdel docker >/dev/null 2>&1 || true

# ---------- 5. 核对 ----------
echo ""
echo "==> [5/6] 核对清理结果 ..."
LEFTOVER="$(dpkg -l 2>/dev/null | awk '/^ii/ {print $2}' | grep -E 'docker|containerd' || true)"
if [ -n "$LEFTOVER" ]; then
  echo "    注意：仍有以下包残留（一般是依赖包，不影响重装）："
  echo "$LEFTOVER" | sed 's/^/      /'
else
  echo "    系统已无任何 Docker 痕迹 ✔"
fi

# ---------- 6. 选择是否立即重装 ----------
echo ""
echo "==> [6/6] 清理完成！"
echo ""
echo "是否现在重新安装？"
echo "  ce  = Docker CE 正式版（官方源，推荐）"
echo "  io  = docker.io 极简版（Ubuntu 自带源）"
echo "  n   = 不装，稍后自己手动装"
read -r -p "请选择 [ce/io/n]：" choice

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$choice" in
  ce|CE)
    if [ -f "$SCRIPT_DIR/filebrowser安装脚本.sh" ]; then
      bash "$SCRIPT_DIR/filebrowser安装脚本.sh"
    else
      echo "!! 未找到 $SCRIPT_DIR/filebrowser安装脚本.sh"
      echo "   请把安装脚本和本脚本放在同一目录后重试。"
    fi
    ;;
  io|IO)
    if [ -f "$SCRIPT_DIR/filebrowser安装脚本-极简版.sh" ]; then
      bash "$SCRIPT_DIR/filebrowser安装脚本-极简版.sh"
    else
      echo "!! 未找到 $SCRIPT_DIR/filebrowser安装脚本-极简版.sh"
      echo "   请把安装脚本和本脚本放在同一目录后重试。"
    fi
    ;;
  *)
    echo "好的，已跳过重装。之后需要时运行任一安装脚本即可。"
    ;;
esac
