# File Browser 使用说明（Ubuntu 26.04 + 手机访问）

通过 File Browser 把电脑上的文件夹共享到局域网，手机浏览器直接打开即可**在线播放视频、直接预览图片**，无需下载。

**文件清单：**

| 文件 | 用途 | 使用频率 |
| --- | --- | --- |
| `filebrowser安装脚本.sh` | 安装 Docker CE 正式版 | 仅首次 |
| `filebrowser安装脚本-极简版.sh` | 安装 docker.io（备用方案） | 仅首次，二选一 |
| `filebrowser启动脚本.sh` | 启动/关闭 File Browser 服务 | 每次使用 |
| `filebrowser清理重装.sh` | 彻底卸载所有 Docker 并重装 | 出问题时 |

---

## 一、首次安装（只做一次）

提供两个安装脚本，**任选一个执行即可，不要都跑**：

### 方案 A：正式版（默认推荐）

```bash
bash filebrowser安装脚本.sh
```

安装 Docker CE（官方仓库，自动适配 Ubuntu 26.04 代号 resolute）。

### 方案 B：极简版（备用）

```bash
bash filebrowser安装脚本-极简版.sh
```

安装 Ubuntu 自带仓库的 `docker.io`。

### 两个版本的区别

| 对比项 | 正式版（Docker CE） | 极简版（docker.io） |
| --- | --- | --- |
| 软件来源 | Docker 官方 APT 仓库 | Ubuntu 自带仓库 |
| 版本新旧 | 新，跟随 Docker 官方发布 | 偏旧，由 Ubuntu 社区打包 |
| 安装步骤 | 需配置 GPG 密钥 + 第三方仓库 | 一行 `apt install` |
| 网络要求 | 需能访问 download.docker.com | 只需 Ubuntu 官方源，国内镜像站即可 |
| 自带组件 | 含 buildx、compose 等官方插件 | 基础功能，无官方插件 |
| 出问题概率 | 仓库/网络环节多，步骤繁琐 | 极少失败 |

### 怎么选

- **先用正式版**：功能全、版本新，顺利装完就不用管极简版
- **正式版卡住或报错**（网络不通、仓库没有 26.04 索引等）：换极简版，对于"跑 File Browser 给手机看视频"这个用途，两者**体验完全一样**

> 两个脚本都会完成相同的收尾工作：把当前用户加入 `docker` 组（免 sudo）、禁止 Docker 开机自启、拉取 File Browser 镜像。

### 安装过程中的交互配置

软件装完后，脚本会**依次要求你完成两步配置**，不配置完不会结束：

**第 1 步：设置登录账号**

- 输入用户名（直接回车用 `admin`）
- 输入密码（输入时不显示，需输入两次确认）
- **密码至少 12 位**，这是 File Browser 的硬性要求，不足会被拒绝并要求重输

**第 2 步：配置共享目录（可添加多个）**

- 输入第一个共享目录路径（直接回车用默认 `~/Videos`）
- 之后可继续逐条添加更多目录，直接回车结束
- 路径支持 `~` 开头；目录不存在时会问你是否创建
- 手机端会看到每个目录最后一级的名字（如 `电影`、`图片`），重名会自动加序号

配置保存在 `~/.filebrowser/install.conf`（仅本人可读），**每次启动都会以它为准**：改了账号密码或目录，重启启动脚本即生效。

安装完成后**必须**让 docker 组权限生效（Ubuntu 26.04 默认没有 `newgrp` 命令，用下面方式代替）：

```bash
su - $USER           # 方式一：输入登录密码，当前终端立即生效（用 exit 可退回）
# 或者直接注销系统重新登录
```

## 二、日常使用

```bash
bash filebrowser启动脚本.sh
```

启动后终端会显示访问地址，例如：

```javascript
http://192.168.1.100:8080
```

1. 确保**手机和电脑连接同一个 Wi-Fi**
2. 手机浏览器（Safari / Chrome / 夸克等均可）打开该地址
3. 用**安装时设置的账号密码**登录（终端菜单里会显示用户名）

启动后终端会一直显示常驻操作菜单：

```javascript
 操作选项（按对应按键即可，无需回车）：

   q  = 仅退出 File Browser 和 WebDAV（其他 Docker 服务保持运行）
   a  = 关闭全部（会先列出当前运行的 Docker 实例，二次确认）

 也可以按 Ctrl+C 或直接点 X 关窗，均会弹出二次确认。
```

### 关闭服务（四种方式）

**方式一：按 `q`** → 仅退出 File Browser，jellyfin 等其他 Docker 服务不受影响。

**方式二：按 `a`** → 先列出当前正在运行的 Docker 实例（含名称和镜像），再要求输入 `y` 二次确认，确认后停止全部实例；输入其他内容则取消、返回菜单。

**方式三：按 `Ctrl+C`** → 终端内文字提示：

```javascript
检测到还有 3 个 Docker 实例正在运行：

  1. jellyfin
  2. open-webui
  3. immich

是否关闭 Docker？

输入：
  y  = 退出 File Browser，并关闭 Docker
  q  = 仅退出 File Browser，保持其他 Docker 服务运行
```

**方式四：点 X 关闭终端窗口** → 终端虽然没了，但桌面会**弹出图形确认窗口**（类似下载器的退出确认），列出正在运行的实例，点击按钮选择：

- 「全部关闭（含以上服务）」：停止全部 Docker 实例
- 「仅退出 File Browser」：其余服务不受影响

**特例：SSH 断连等完全无法交互的情况** → 安全兜底，仅退出 File Browser，不动其他服务。

> 整个过程只在关闭动作发生的那一刻触发一次，没有轮询和定时器，平时零开销。

## 三、自定义配置

账号、密码、共享目录列表都保存在 `~/.filebrowser/install.conf`，**直接改这个文件、重启启动脚本即生效**：

```bash
nano ~/.filebrowser/install.conf
```

```javascript
FB_USER=myname          # 登录用户名
FB_PASS=mypassword      # 登录密码
FB_SHARES=(             # 共享目录列表，一行一个
  /home/cince/Videos
  /run/media/cince/DATA/电影
)
```

临时性调整（不改配置文件，仅本次生效）：

| 需求 | 命令 |
| --- | --- |
| 临时共享某个目录 | `SHARE_DIR=/home/你的用户名/电影 bash filebrowser启动脚本.sh` |
| 换端口（如 9090） | `PORT=9090 bash filebrowser启动脚本.sh` |
| 两者一起 | `PORT=9090 SHARE_DIR=~/Downloads bash filebrowser启动脚本.sh` |

## 四、手机端体验说明

### 两个入口

启动脚本会同时拉起两个服务，共用同一套账号密码和共享目录：

| 入口 | 地址 | 用途 |
| --- | --- | --- |
| File Browser 网页 | `http://电脑IP:8080` | 浏览器管理文件、看图、传文件 |
| WebDAV | `http://电脑IP:8081` | **手机第三方播放器看视频（主力）** |

### 看视频推荐：播放器 + WebDAV

网页内置播放器能力有限（格式支持少、无倍速、无字幕控制），看视频请用专业播放器直连 WebDAV：

- **安卓 VLC**：侧边栏 → 网络 → 右上角 + → WebDAV，主机填 `电脑IP`，端口 `8081`，账号密码同 File Browser
- **安卓 nPlayer / MX Player / Solid Explorer**：新建连接 → 选 WebDAV → 填同上
- **iOS Infuse / nPlayer / VLC**：添加共享 → WebDAV → 填同上

添加一次后播放器会记住，以后打开 App 直接浏览文件夹点播，硬解、字幕、倍速、进度记忆全支持。

### 网页端能力边界

- **视频**：MP4（H.264/H.265 编码）可直接在线播放，支持拖动进度条；其他格式请走 WebDAV + 播放器
- **图片**：JPG / PNG / GIF / WebP 点开即预览，无需下载
- 网页端临时分享单个文件给播放器：生成分享链接后，把 `/share/xxx` 改为 `/api/public/dl/xxx` 即为免登录直链

## 五、彻底清理并重装

如果安装过程出问题、或想从零开始（会删除**所有** Docker 容器和镜像，包括 jellyfin 等其他服务）：

```bash
bash filebrowser清理重装.sh
```

脚本会自动检测并卸载系统里所有版本的 Docker（apt 的 docker.io / docker-ce、snap 版都会查），清空 `/var/lib/docker` 等全部数据，最后可选择立即重装。`~/Videos` 里的视频文件不会被删除。需要输入大写 `YES` 确认才会执行。

## 六、常见问题

**1. 手机打不开地址？**
检查防火墙是否放行端口：

```bash
sudo ufw allow 8080/tcp
```

并确认手机和电脑在同一局域网（部分路由器开启了“AP 隔离”会导致互访失败，需在路由器后台关闭）。

**2. 提示 `permission denied ... docker.sock`？**
docker 组权限未生效（通常发生在刚装完 Docker 的同一终端里）。注意 Ubuntu 26.04 默认**没有 `newgrp` 命令**，请改用：

```bash
su - $USER        # 输入登录密码，当前终端立即生效
# 或注销系统重新登录
```

验证：`groups | grep docker`，能看到 docker 即生效。

**3. 提示端口被占用？**
换个端口启动：`PORT=9090 bash filebrowser启动脚本.sh`

**4. 忘记密码？**
账号密码保存在 `~/.filebrowser/install.conf` 里，直接查看即可：

```bash
cat ~/.filebrowser/install.conf
```

想改密码就编辑该文件里的 `FB_PASS`，重启启动脚本即生效（每次启动都会强制同步配置文件里的账号密码）。若使用了自定义用户名，默认的 `admin` 账号会被自动移除，避免弱口令入口。

**5. 电脑 IP 变了？**
路由器重新分配 IP 后地址会变，启动脚本每次都会显示当前最新地址，以终端显示为准。

**6. 开机后会自动启动吗？**
不会。安装脚本只装软件，并已禁用 Docker 的开机自启（含 `docker.socket` 套接字激活）；File Browser 容器是 `--restart no` 且退出即删除。重启电脑后两者都处于停止状态，需要时手动运行启动脚本即可（脚本会先自动拉起 Docker 服务）。

**7. 提示“权限不够 / Permission denied”，加 sudo 也没用？**
脚本放在 NTFS / exFAT 数据盘（如 `/run/media/...`）时会出现，这类分区不支持 Linux 执行权限。两种解法：

```bash
# 方法一：用 bash 解释执行（只需读权限，立即可用）
bash "/脚本所在路径/filebrowser启动脚本.sh"

# 方法二：复制到主目录后用（推荐，以后可双击运行）
mkdir -p ~/filebrowser
cp /脚本所在路径/*.sh ~/filebrowser/
chmod +x ~/filebrowser/*.sh
```