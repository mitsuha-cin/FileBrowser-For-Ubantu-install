#!/usr/bin/env bash
# =============================================================
# File Browser 启动脚本
# 流程：启动 Docker → 启动 File Browser 容器 → 打印常驻操作菜单待命
#
# 退出方式（均带二次确认）：
#   · 按 q   = 仅退出 File Browser，其他 Docker 服务保持运行
#   · 按 a   = 关闭全部：先列出当前运行的 Docker 实例，确认后停止
#   · Ctrl+C = 终端内文字提示 y/q
#   · 点 X 关窗 = 桌面弹出图形确认框（类似下载器的退出确认）
#
# 用法：bash filebrowser启动脚本.sh
# 登录账号与共享目录在安装脚本中配置，保存于 ~/.filebrowser/install.conf
# 临时共享单个目录：SHARE_DIR=/home/你的用户名/电影 bash filebrowser启动脚本.sh
# 自定义端口：      PORT=9090 bash filebrowser启动脚本.sh
# =============================================================
set -euo pipefail

# ---------- 可配置项 ----------
CONTAINER_NAME="filebrowser"
PORT="${PORT:-8080}"                          # File Browser 网页端口
WEBDAV_CONTAINER="filebrowser-webdav"         # WebDAV 容器（手机第三方播放器用）
WEBDAV_PORT="${WEBDAV_PORT:-8081}"            # WebDAV 端口
DATA_DIR="$HOME/.filebrowser"
DB_PATH="$DATA_DIR/filebrowser.db"
SETTINGS_PATH="$DATA_DIR/settings.json"
IMAGE="filebrowser/filebrowser:latest"
DAV_IMAGE="sigoden/dufs:latest"               # 轻量 WebDAV 服务镜像
CONF_FILE="$DATA_DIR/install.conf"

# 读取安装阶段保存的配置（登录账号 / 共享目录列表）
FB_USER="admin"
FB_PASS="admin"
FB_SHARES=()
CONFIG_LOADED=0
if [ -f "$CONF_FILE" ]; then
  # shellcheck disable=SC1090
  . "$CONF_FILE"
  CONFIG_LOADED=1
else
  echo "!! 未找到安装配置（$CONF_FILE）"
  echo "   将使用默认账号 admin/admin、默认目录 ~/Videos。"
  echo "   建议先运行安装脚本完成初始配置。"
fi

# 环境变量 SHARE_DIR 可临时覆盖配置（仅单个目录）
if [ -n "${SHARE_DIR:-}" ]; then
  FB_SHARES=("$SHARE_DIR")
fi
if ((${#FB_SHARES[@]} == 0)); then
  FB_SHARES=("$HOME/Videos")
fi

# 加载即校验：密码不足 12 位时当场重新设置并回写配置，
# 不等到写数据库才报错（兼容旧版安装脚本生成的配置）
if [ "$CONFIG_LOADED" -eq 1 ] && [ ${#FB_PASS} -lt 12 ]; then
  echo "!! 配置中的密码不足 12 位（File Browser 硬性要求），请重新设置："
  while true; do
    read -rs -p "请输入新密码（至少 12 位，输入时不显示）：" new_pass
    echo ""
    if [ ${#new_pass} -lt 12 ]; then
      echo "!! 不足 12 位，请重新输入"
      continue
    fi
    read -rs -p "请再次输入密码确认：" new_pass2
    echo ""
    if [ "$new_pass" = "$new_pass2" ]; then
      FB_PASS="$new_pass"
      break
    fi
    echo "!! 两次输入不一致，请重新输入"
  done
  # 回写配置文件，一次修正永久生效
  {
    printf 'FB_USER=%q\n' "$FB_USER"
    printf 'FB_PASS=%q\n' "$FB_PASS"
    echo "FB_SHARES=("
    for s in "${FB_SHARES[@]}"; do printf '  %q\n' "$s"; done
    echo ")"
  } > "$CONF_FILE"
  chmod 600 "$CONF_FILE"
  echo "==> 新密码已保存到 $CONF_FILE"
fi

# ---------- 停止全部 Docker 实例（含 File Browser） ----------
shutdown_all() {
  trap - EXIT INT TERM HUP   # 主动退出，摘掉信号陷阱防止二次触发
  echo "==> 正在关闭 Docker 上的全部实例 ..."
  local ids
  ids="$(docker ps -q 2>/dev/null || true)"
  if [ -n "$ids" ]; then
    # shellcheck disable=SC2086
    docker stop $ids >/dev/null 2>&1 || true
  fi
  docker rm -f "$CONTAINER_NAME" "$WEBDAV_CONTAINER" >/dev/null 2>&1 || true
  echo "==> 已全部关闭（含 File Browser 与 WebDAV）。"
}

# ---------- 仅退出 File Browser（含配套的 WebDAV 容器） ----------
shutdown_self() {
  trap - EXIT INT TERM HUP   # 主动退出，摘掉信号陷阱防止二次触发
  docker rm -f "$CONTAINER_NAME" "$WEBDAV_CONTAINER" >/dev/null 2>&1 || true
  echo "==> 仅退出 File Browser（含 WebDAV），其他 Docker 实例保持运行。"
}

# ---------- 清理函数（仅在信号触发时执行，无轮询、无定时器） ----------
cleanup() {
  trap - EXIT INT TERM HUP   # 防止重复触发
  echo ""
  echo "==> 正在退出 File Browser ..."

  # 查询除 filebrowser / webdav 外仍在运行的 Docker 实例
  local others=()
  mapfile -t others < <(docker ps --format '{{.Names}}' 2>/dev/null | grep -vx "$CONTAINER_NAME" | grep -vx "$WEBDAV_CONTAINER" || true)

  # 没有其他实例 → 直接静默清理
  if ((${#others[@]} == 0)); then
    docker rm -f "$CONTAINER_NAME" "$WEBDAV_CONTAINER" >/dev/null 2>&1 || true
    echo "==> 清理完成，File Browser 已关闭。"
    exit 0
  fi

  # 拼实例清单（终端文字和图形弹窗共用）
  local list_text="" i
  for i in "${!others[@]}"; do
    list_text+="  $((i + 1)). ${others[$i]}\n"
  done

  # 情况一：终端还活着（Ctrl+C / 正常退出）→ 终端内文字提示
  if { exec 9</dev/tty; } 2>/dev/null; then
    echo "检测到还有 ${#others[@]} 个 Docker 实例正在运行："
    echo ""
    printf '%b' "$list_text"
    echo ""
    echo "是否关闭 Docker？"
    echo ""
    echo "输入："
    echo "  y  = 退出 File Browser，并关闭 Docker"
    echo "  q  = 仅退出 File Browser，保持其他 Docker 服务运行"
    echo ""
    local ans=""
    read -r -p "请输入 [y/q]：" ans <&9
    exec 9<&-
    case "$ans" in
      y|Y) shutdown_all ;;
      *)   shutdown_self ;;
    esac
    exit 0
  fi

  # 情况二：终端已被销毁（点 X 关窗）→ 桌面弹出图形确认框，阻塞等待点击
  if command -v zenity >/dev/null 2>&1; then
    local msg="检测到还有 ${#others[@]} 个 Docker 实例正在运行：\n\n${list_text}\n是否关闭 Docker？"
    if zenity --question \
        --title="File Browser 退出确认" \
        --width=460 \
        --text="$(printf '%b' "$msg")" \
        --ok-label="全部关闭（含以上服务）" \
        --cancel-label="仅退出 File Browser" 2>/dev/null; then
      shutdown_all
    else
      shutdown_self
    fi
  else
    # 情况三：无任何可交互途径（SSH 断连 / 无图形环境）→ 安全兜底
    echo "!! 无法显示提示（无终端且无图形环境）→ 仅退出 File Browser，其他实例保持运行"
    shutdown_self
  fi
  exit 0
}

# 关闭终端(SIGHUP) / Ctrl+C(SIGINT) / 被kill(SIGTERM) / 脚本结束(EXIT) 触发清理
trap cleanup EXIT INT TERM HUP

# ---------- 1. 启动 Docker 服务 ----------
echo "==> [1/3] 检查并启动 Docker 服务"
if ! systemctl is-active --quiet docker; then
  sudo systemctl start docker
fi

# 前置检查：当前用户能否使用 docker（docker 组权限）
if ! docker info >/dev/null 2>&1; then
  echo ""
  echo "!! 权限不足，无法连接 Docker（/var/run/docker.sock）"
  echo "   原因：安装脚本已把你加入 docker 组，但当前终端是加组之前打开的。"
  echo "   解决（二选一，26.04 默认无 newgrp 命令）："
  echo "     1) 执行  su - \$USER  （输入登录密码）后重新运行本脚本"
  echo "     2) 注销系统重新登录"
  echo "   验证：groups | grep docker  （能看到 docker 即生效）"
  exit 1
fi

# 镜像不存在则拉取
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "==> 首次运行，拉取镜像 $IMAGE"
  docker pull "$IMAGE"
fi

# zenity 用于点 X 关窗时弹出图形确认框（Ubuntu 桌面通常自带，缺失则自动安装）
if ! command -v zenity >/dev/null 2>&1; then
  echo "==> 安装 zenity（点 X 关窗时的图形确认框组件）"
  sudo apt install -y zenity >/dev/null 2>&1 || \
    echo "!! zenity 安装失败：点 X 关窗时将无法弹窗，自动退化为仅退出 File Browser"
fi

# ---------- 2. 启动 File Browser 容器 ----------
echo "==> [2/3] 启动 File Browser 容器"
for d in "${FB_SHARES[@]}"; do mkdir -p "$d"; done
mkdir -p "$DATA_DIR"

# 源头防线①：数据库路径必须是"文件"。
# 若为目录（历史异常遗留），Docker 会错挂导致账号库无法初始化 → 删掉重建
if [ -d "$DB_PATH" ]; then
  echo "==> 检测到数据库路径是目录（异常遗留），正在修正 ..."
  rm -rf "$DB_PATH"
fi
touch "$DB_PATH"

# 源头防线②-b：自写 settings.json 并挂载进容器，强制数据库路径为 /database.db。
# 新版镜像默认用 /config/settings.json（指向匿名卷里的 /database/filebrowser.db），
# 不固定的话服务器会无视我们挂载的数据库文件，导致账号配置全部落空。
cat > "$SETTINGS_PATH" <<'EOF'
{
  "port": 80,
  "baseURL": "",
  "address": "",
  "log": "stdout",
  "database": "/database.db",
  "root": "/srv"
}
EOF

# 源头防线②：数据目录属主必须是当前用户（防止曾用 sudo 运行导致 root 占用）
if [ "$(stat -c %U "$DATA_DIR")" != "$USER" ]; then
  echo "==> 修正数据目录属主 ..."
  sudo chown -R "$USER:$USER" "$DATA_DIR"
fi

# 清理可能残留的同名旧容器
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

# 组装共享目录挂载：每个目录映射到 /srv/目录名
# 完全重复的路径直接跳过；不同路径但重名的自动加序号
MOUNT_ARGS=()
SHARE_NAMES=()        # 有效路径对应的显示名（WebDAV 容器复用，保证两边一致）
EFFECTIVE_PATHS=()    # 去重后的实际路径，与 SHARE_NAMES 一一对应
declare -A USED_NAMES=()
declare -A USED_SRC=()
for d in "${FB_SHARES[@]}"; do
  if [ -n "${USED_SRC[$d]:-}" ]; then
    echo "    跳过重复路径：$d"
    continue
  fi
  USED_SRC[$d]=1
  base="$(basename "$d")"
  name="$base"; n=2
  while [ -n "${USED_NAMES[$name]:-}" ]; do
    name="${base}_${n}"; n=$((n + 1))
  done
  USED_NAMES[$name]=1
  SHARE_NAMES+=("$name")
  EFFECTIVE_PATHS+=("$d")
  MOUNT_ARGS+=(-v "$d:/srv/$name")
done

# 源头防线③：数据库初始化与账号配置必须在【服务器启动前】用一次性容器完成。
# 原因：File Browser 的 Bolt 数据库是独占锁，服务器运行时任何 CLI 操作都会
#       timeout 失败——所以顺序是：先初始化/配置 → 再启动服务。
fb_cli() {
  docker run --rm -v "$DB_PATH":/database.db "$IMAGE" -d /database.db "$@"
}

if [ ! -s "$DB_PATH" ]; then
  echo "==> 初始化账号数据库 ..."
  fb_cli config init >/dev/null
fi

if [ "$CONFIG_LOADED" -eq 1 ]; then
  echo "==> 应用登录账号配置（用户：$FB_USER）"
  if ! fb_cli users add "$FB_USER" "$FB_PASS" --perm.admin >/dev/null 2>&1; then
    # 用户已存在则更新密码
    if ! fb_cli users update "$FB_USER" --password "$FB_PASS" >/dev/null 2>&1; then
      echo "!! 账号配置失败，File Browser 原始报错如下："
      fb_cli users add "$FB_USER" "$FB_PASS" --perm.admin || true
      echo ""
      echo "   常见原因：密码少于 12 位（硬性要求）。"
      echo "   解决：nano ~/.filebrowser/install.conf 修改 FB_PASS 后重新运行本脚本。"
      exit 1
    fi
  fi
  # 使用自定义账号后移除默认 admin，避免弱口令入口
  if [ "$FB_USER" != "admin" ]; then
    fb_cli users rm admin >/dev/null 2>&1 || true
  fi
fi

docker run -d \
  --name "$CONTAINER_NAME" \
  --restart no \
  -p "${PORT}:80" \
  "${MOUNT_ARGS[@]}" \
  -v "$DB_PATH":/database.db \
  -v "$SETTINGS_PATH":/config/settings.json:ro \
  -e TZ=Asia/Shanghai \
  "$IMAGE" >/dev/null

# 源头防线④：启动后通过 HTTP 健康检查验证服务真正可用（不碰数据库锁）
echo "==> 验证服务可用性 ..."
svc_ok=0
for _ in $(seq 1 10); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/health" 2>/dev/null || true)"
  if [ "$code" = "200" ]; then
    svc_ok=1
    break
  fi
  sleep 1
done
if [ "$svc_ok" -ne 1 ]; then
  echo "!! 服务未通过健康检查。请执行 docker logs $CONTAINER_NAME 查看原因；"
  echo "   反复失败请执行 filebrowser清理重装.sh 后重装。"
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  exit 1
fi

# ---------- 2b. 启动 WebDAV 服务（手机第三方播放器专用通道） ----------
echo "==> 启动 WebDAV 服务（端口：$WEBDAV_PORT，供 VLC / nPlayer 等播放器使用）"

if ! docker image inspect "$DAV_IMAGE" >/dev/null 2>&1; then
  echo "==> 首次运行，拉取镜像 $DAV_IMAGE"
  docker pull "$DAV_IMAGE"
fi

# 与 File Browser 使用完全相同的显示名，挂载到 /data/ 下
DAV_MOUNT_ARGS=()
for i in "${!SHARE_NAMES[@]}"; do
  DAV_MOUNT_ARGS+=(-v "${EFFECTIVE_PATHS[$i]}:/data/${SHARE_NAMES[$i]}")
done

docker rm -f "$WEBDAV_CONTAINER" >/dev/null 2>&1 || true

docker run -d \
  --name "$WEBDAV_CONTAINER" \
  --restart no \
  -p "${WEBDAV_PORT}:5000" \
  "${DAV_MOUNT_ARGS[@]}" \
  -e TZ=Asia/Shanghai \
  "$DAV_IMAGE" -A -a "${FB_USER}:${FB_PASS}@/:rw" /data >/dev/null

# 健康检查（返回 401 表示服务正常且要求认证）
dav_ok=0
for _ in $(seq 1 5); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${WEBDAV_PORT}/" 2>/dev/null || true)"
  if [ "$code" = "200" ] || [ "$code" = "401" ]; then
    dav_ok=1
    break
  fi
  sleep 1
done
if [ "$dav_ok" -ne 1 ]; then
  echo "!! WebDAV 服务未就绪（不影响 File Browser 使用）"
  echo "   排查：docker logs $WEBDAV_CONTAINER"
fi

# ---------- 3. 显示访问地址并进入常驻操作菜单 ----------
LAN_IP="$(hostname -I | awk '{print $1}')"

print_menu() {
  echo ""
  echo "============================================================"
  echo " 网页浏览（File Browser）：http://${LAN_IP}:${PORT}"
  echo " 播放器专用（WebDAV）：    http://${LAN_IP}:${WEBDAV_PORT}"
  echo " 登录账号： $FB_USER（两个入口共用同一账号密码）"
  echo ""
  echo " 共享目录："
  local d
  for d in "${FB_SHARES[@]}"; do
    echo "   · $d"
  done
  echo "============================================================"
  echo ""
  echo " 操作选项（按对应按键即可，无需回车）："
  echo ""
  echo "   q  = 仅退出 File Browser 和 WebDAV（其他 Docker 服务保持运行）"
  echo "   a  = 关闭全部（会先列出当前运行的 Docker 实例，二次确认）"
  echo ""
  echo " 也可以按 Ctrl+C 或直接点 X 关窗，均会弹出二次确认。"
  echo ""
}

echo "==> [3/3] File Browser 已启动！"
print_menu

# 常驻待命：等待按键（无轮询、无定时器，read 阻塞零开销）
while true; do
  if ! read -rsn1 key 2>/dev/null; then
    # 终端输入已不可用（如窗口被关闭），交给信号陷阱处理；
    # 退化为等待容器退出，避免空转
    docker wait "$CONTAINER_NAME" >/dev/null 2>&1 || true
    exit 0
  fi
  case "$key" in
    q|Q)
      shutdown_self
      exit 0
      ;;
    a|A)
      echo ""
      echo "==> 当前正在运行的 Docker 实例："
      docker ps --format '  · {{.Names}}（{{.Image}}）' 2>/dev/null || true
      echo ""
      read -r -p "确认全部关闭？[y/N]：" confirm_all
      case "$confirm_all" in
        y|Y)
          shutdown_all
          exit 0
          ;;
        *)
          echo "==> 已取消，File Browser 继续运行。"
          print_menu
          ;;
      esac
      ;;
  esac
done
