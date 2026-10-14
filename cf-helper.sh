#!/bin/bash

# ==============================================================================
#  cf-helper.sh - Cloudflared 连接助手 (v3.6)
#  - 支持 Linux 和 macOS 的 cloudflared 官方发行包
#  - 二进制文件始终相对于脚本(真实)目录查找/下载，支持通过符号链接调用
#  - 找不到按架构命名的文件时，复用脚本目录中的 cloudflared 或 PATH 里已安装的版本
#  - 增加了对端口号的有效性验证 (1-65535)
#  - 增加了对周知端口 (< 1024) 的警告
# ==============================================================================

# 本脚本大量使用 bash 特性（[[ ]]、BASH_SOURCE、BASH_REMATCH、EUID …）。
# 若被 `sh cf-helper.sh` 这样调用，直接用 bash 重新执行自身，
# 否则会抛出一连串 "[[: not found" / "Bad substitution" 之类的误导性错误。
if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    fi
    echo "错误：本脚本需要 bash 才能运行，请先安装 bash。" >&2
    exit 1
fi

set -euo pipefail

DEFAULT_PORT=21128

show_help() {
    cat <<'EOF'
Cloudflared 连接助手 (cf-helper.sh)

用法: ./cf-helper.sh [HOSTNAME] [PORT]

参数:
  HOSTNAME   (可选) 您要连接的隧道地址 (e.g., tunnel.example.com)。
  PORT       (可选) 本地监听的 TCP 端口 (1-65535)。如果未提供，默认为 21128。

如果未提供任何参数，脚本将以交互模式启动，依次询问所需信息。
当前支持 Linux 和 macOS；其他系统可以将匹配的 cloudflared 文件放在脚本目录中手动使用。
EOF
}

# 0. 显示帮助信息
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
    exit 0
fi

if (( $# > 2 )); then
    echo "错误：最多只能提供 HOSTNAME 和 PORT 两个参数。" >&2
    show_help >&2
    exit 2
fi

# 1. 确定脚本目录。不要依赖调用脚本时的当前工作目录。
#    若脚本是通过符号链接调用的（例如 ln -s 到 ~/.local/bin 以便全局使用），
#    必须沿着链接找到真实文件，否则会跑到链接所在的目录里去找/下载 cloudflared。
#    这里不用 readlink -f：macOS 12.3 之前的 BSD readlink 不支持 -f。
resolve_script_dir() {
    local source="${BASH_SOURCE[0]}"
    local dir
    while [[ -L "$source" ]]; do
        dir=$(cd "$(dirname "$source")" >/dev/null 2>&1 && pwd -P) || return 1
        source=$(readlink "$source") || return 1
        # 相对路径的链接目标是相对于链接自身所在目录的
        [[ "$source" == /* ]] || source="$dir/$source"
    done
    cd "$(dirname "$source")" >/dev/null 2>&1 && pwd -P
}
SCRIPT_DIR=$(resolve_script_dir) || {
    echo "错误：无法确定脚本所在目录。" >&2
    exit 1
}

# 2. 根据操作系统和架构匹配官方 cloudflared 发行包
OS=$(uname -s)
ARCH=$(uname -m)
CLOUDFLARED_BINARY=""
CLOUDFLARED_ASSET=""
DOWNLOAD_KIND="binary"
KNOWN_PLATFORM=false

# Apple Silicon 上若终端/shell 运行在 Rosetta 2 之下，uname -m 会报告 x86_64。
# 此时应改用原生 arm64 版本：arm64 可执行文件可以从 x86_64 进程中直接启动，
# 没必要让 cloudflared 也跟着走转译。
if [[ "$OS" == "Darwin" && "$ARCH" == "x86_64" ]] && \
    [[ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" == "1" ]]; then
    ARCH="arm64"
fi

case "${OS}:${ARCH}" in
    Linux:x86_64|Linux:amd64)
        CLOUDFLARED_BINARY="$SCRIPT_DIR/cloudflared-linux-amd64"
        CLOUDFLARED_ASSET="cloudflared-linux-amd64"
        KNOWN_PLATFORM=true
        ;;
    Linux:i386|Linux:i486|Linux:i586|Linux:i686)
        CLOUDFLARED_BINARY="$SCRIPT_DIR/cloudflared-linux-386"
        CLOUDFLARED_ASSET="cloudflared-linux-386"
        KNOWN_PLATFORM=true
        ;;
    Linux:aarch64|Linux:arm64)
        CLOUDFLARED_BINARY="$SCRIPT_DIR/cloudflared-linux-arm64"
        CLOUDFLARED_ASSET="cloudflared-linux-arm64"
        KNOWN_PLATFORM=true
        ;;
    # 官方 cloudflared-linux-arm 以 GOARM=5（软浮点）编译，是 32 位 ARM 的"通用"版本：
    # 既能跑在 armv6（树莓派 1 / Zero），也能跑在 armv7 以及 32 位用户态的 armv8 系统上。
    Linux:arm|Linux:armv6l|Linux:armv7l|Linux:armv8l|Linux:armhf)
        CLOUDFLARED_BINARY="$SCRIPT_DIR/cloudflared-linux-arm"
        CLOUDFLARED_ASSET="cloudflared-linux-arm"
        KNOWN_PLATFORM=true
        ;;
    Darwin:x86_64|Darwin:amd64)
        CLOUDFLARED_BINARY="$SCRIPT_DIR/cloudflared-darwin-amd64"
        CLOUDFLARED_ASSET="cloudflared-darwin-amd64.tgz"
        DOWNLOAD_KIND="darwin-archive"
        KNOWN_PLATFORM=true
        ;;
    Darwin:arm64|Darwin:aarch64)
        CLOUDFLARED_BINARY="$SCRIPT_DIR/cloudflared-darwin-arm64"
        CLOUDFLARED_ASSET="cloudflared-darwin-arm64.tgz"
        DOWNLOAD_KIND="darwin-archive"
        KNOWN_PLATFORM=true
        ;;
esac

# 下载被中断（Ctrl-C、终端断开）时，mktemp 出来的半成品不会自己消失，
# 会在脚本目录里留下一堆 cloudflared-*.tmp.XXXXXX。用 trap 兜底清理。
DOWNLOAD_TMP=""
EXTRACT_DIR=""
cleanup_temp() {
    if [[ -n "$DOWNLOAD_TMP" ]]; then
        rm -f "$DOWNLOAD_TMP"
        DOWNLOAD_TMP=""
    fi
    if [[ -n "${EXTRACT_DIR:-}" ]]; then
        rm -rf "$EXTRACT_DIR"
        EXTRACT_DIR=""
    fi
}
trap cleanup_temp EXIT
# Ctrl-C 时终端只会回显 ^C 而不换行，下一个 shell 提示符会紧跟在 ^C 后面；补一个换行。
trap 'echo >&2; exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# 下载到临时文件后再原子替换目标，避免中断后留下一个看似可用的残缺文件
download_file() {
    local url="$1"
    local destination="$2"

    if ! DOWNLOAD_TMP=$(mktemp "${destination}.tmp.XXXXXX"); then
        echo "错误：无法在目标目录创建临时文件：$destination" >&2
        return 1
    fi
    local tmp_file="$DOWNLOAD_TMP"

    if command -v curl >/dev/null 2>&1; then
        # --connect-timeout 只约束建连阶段；传输中途网络"假死"时 curl 会一直挂着。
        # --speed-limit/--speed-time：连续 30 秒低于 1 KiB/s 就视为失败并交给 --retry 重试。
        # --proto/--proto-redir：即使 GitHub 的跳转被篡改，也不允许降级到明文 http。
        if ! curl --fail --location --show-error --retry 3 --connect-timeout 15 \
            --speed-limit 1024 --speed-time 30 \
            --proto '=https' --proto-redir '=https' \
            --output "$tmp_file" "$url"; then
            rm -f "$tmp_file"
            DOWNLOAD_TMP=""
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget --tries=3 --timeout=15 --output-document="$tmp_file" "$url"; then
            rm -f "$tmp_file"
            DOWNLOAD_TMP=""
            return 1
        fi
    else
        echo "错误：需要 curl 或 wget 来下载文件，但两者都未安装。" >&2
        rm -f "$tmp_file"
        DOWNLOAD_TMP=""
        return 1
    fi

    if [[ ! -s "$tmp_file" ]]; then
        echo "错误：下载结果为空。" >&2
        rm -f "$tmp_file"
        DOWNLOAD_TMP=""
        return 1
    fi

    if ! mv -f "$tmp_file" "$destination"; then
        echo "错误：无法将下载结果写入 '$destination'。" >&2
        rm -f "$tmp_file"
        DOWNLOAD_TMP=""
        return 1
    fi
    DOWNLOAD_TMP=""
}

# 在已知平台上，按架构命名的文件不存在时，先看看用户是否已经用别的方式准备好了
# cloudflared，再决定要不要提议下载 40 MB 的文件：
#   - macOS 官方 .tgz 解压出来的文件名就叫 cloudflared，手动下载的 Mac 用户很容易踩到；
#   - 也可能早就通过 brew / apt 安装到了 PATH 里。
find_existing_cloudflared() {
    local candidate
    if [[ -f "$SCRIPT_DIR/cloudflared" ]]; then
        printf '%s\n' "$SCRIPT_DIR/cloudflared"
        return 0
    fi
    if candidate=$(command -v cloudflared 2>/dev/null) && [[ -n "$candidate" && -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi
    return 1
}

if [[ "$KNOWN_PLATFORM" == true && ! -f "$CLOUDFLARED_BINARY" ]] && \
    EXISTING_BINARY=$(find_existing_cloudflared); then
    echo "提示：未找到 $(basename "$CLOUDFLARED_BINARY")，改用已存在的 cloudflared：$EXISTING_BINARY"
    CLOUDFLARED_BINARY="$EXISTING_BINARY"
fi

# 3. 根据架构类型处理二进制文件
if [[ "$KNOWN_PLATFORM" == true ]]; then
    if [[ ! -f "$CLOUDFLARED_BINARY" ]]; then
        echo "提示：为 '$OS/$ARCH' 设计的二进制文件不存在：$(basename "$CLOUDFLARED_BINARY")"
        if ! IFS= read -r -p "是否要自动从 GitHub 下载最新版本？ (y/n): " choice; then
            # read 在输入末尾缺少换行符（如通过管道传入）时也会返回非零，
            # 但此时 choice 中已包含读取到的内容；仅在确实没有任何输入时才视为取消。
            choice="${choice:-n}"
            echo
        fi

        # 接受 y / Y / yes / Yes / YES；很多人习惯性地会敲完整的 yes。
        if [[ "$choice" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            DOWNLOAD_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/$CLOUDFLARED_ASSET"
            echo "正在从 $DOWNLOAD_URL 下载..."

            if [[ "$DOWNLOAD_KIND" == "darwin-archive" ]]; then
                EXTRACT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cf-helper-download.XXXXXX") || {
                    echo "错误：无法创建临时解压目录。" >&2
                    exit 1
                }
                ARCHIVE_PATH="$EXTRACT_DIR/cloudflared.tgz"
                if ! download_file "$DOWNLOAD_URL" "$ARCHIVE_PATH"; then
                    rm -rf "$EXTRACT_DIR"
                    echo "错误：下载失败。请检查网络连接或下载链接。" >&2
                    exit 1
                fi
                if ! tar -xzf "$ARCHIVE_PATH" -C "$EXTRACT_DIR" || \
                    [[ ! -f "$EXTRACT_DIR/cloudflared" ]]; then
                    rm -rf "$EXTRACT_DIR"
                    echo "错误：下载的 macOS cloudflared 压缩包格式无效。" >&2
                    exit 1
                fi
                if ! chmod +x "$EXTRACT_DIR/cloudflared" || \
                    ! mv -f "$EXTRACT_DIR/cloudflared" "$CLOUDFLARED_BINARY"; then
                    rm -rf "$EXTRACT_DIR"
                    echo "错误：无法安装下载的 cloudflared 文件到 '$CLOUDFLARED_BINARY'。" >&2
                    exit 1
                fi
                rm -rf "$EXTRACT_DIR"
            else
                if ! download_file "$DOWNLOAD_URL" "$CLOUDFLARED_BINARY"; then
                    echo "错误：下载失败。请检查网络连接或下载链接。" >&2
                    exit 1
                fi
            fi
            echo "下载成功。"
        else
            echo "操作已取消。" >&2
            exit 1
        fi
    fi
else
    echo "提示：无法为您的系统 '$OS/$ARCH' 自动匹配官方版本。"
    echo "正在脚本目录中查找用户手动提供的二进制文件 (名称以 'cloudflared' 开头)..."

    CANDIDATES=()
    for candidate in "$SCRIPT_DIR"/cloudflared*; do
        [[ -f "$candidate" ]] && CANDIDATES+=("$candidate")
    done

    if [[ "${#CANDIDATES[@]}" -eq 1 ]]; then
        CLOUDFLARED_BINARY="${CANDIDATES[0]}"
        echo "成功！已找到并选择二进制文件: $CLOUDFLARED_BINARY"
    elif [[ "${#CANDIDATES[@]}" -gt 1 ]]; then
        echo "错误：在脚本目录中找到多个可能的 cloudflared 文件：" >&2
        printf '  %s\n' "${CANDIDATES[@]}" >&2
        echo "请只保留一个，或修改脚本以指定要使用的文件。" >&2
        exit 1
    else
        echo "错误：未能在脚本目录中找到任何以 'cloudflared' 开头的文件。" >&2
        echo "请从 https://github.com/cloudflare/cloudflared/releases 下载适用于您系统 '$OS/$ARCH' 的版本，并将其放置在脚本所在的目录中。" >&2
        exit 1
    fi
fi

# 4. 最终检查并确保文件可执行。
if [[ -z "$CLOUDFLARED_BINARY" || ! -s "$CLOUDFLARED_BINARY" ]]; then
    echo "严重错误：未能定位到可用的 cloudflared 二进制文件。" >&2
    exit 1
fi

if [[ ! -x "$CLOUDFLARED_BINARY" ]]; then
    echo "提示：文件 '$CLOUDFLARED_BINARY' 不是可执行文件，正在尝试添加权限..."
    if ! chmod +x "$CLOUDFLARED_BINARY" || [[ ! -x "$CLOUDFLARED_BINARY" ]]; then
        # 注意：这里不能在双引号字符串内再写一对双引号，否则会把路径"解引用"，
        # 含空格的路径会被拆开，用户照着提示复制出来的命令也会少掉引号。
        echo "错误：无法为文件 '$CLOUDFLARED_BINARY' 设置可执行权限。请手动执行 chmod +x '$CLOUDFLARED_BINARY'。" >&2
        exit 1
    fi
fi

echo ""
echo "脚本已启动，将使用 '$CLOUDFLARED_BINARY' 执行连接。"
echo ""

# 5. 获取并验证连接参数
# -- 获取 Hostname --
# 不用 HOSTNAME 作变量名：它是 bash 自动设置的内建变量（本机主机名），在 Docker 等
# 环境里还是导出的环境变量，覆盖它既容易让读代码的人误解，也会把值泄露给子进程。
TUNNEL_HOSTNAME="${1:-}"
if [[ -n "$TUNNEL_HOSTNAME" ]]; then
    echo "已从命令行参数获取隧道地址: $TUNNEL_HOSTNAME"
fi

# 去掉首尾空白并挡掉明显不可能成为主机名的输入。cloudflared 会把该值拼成
# https://<hostname>，只要含空格就会报 `invalid character " " in host name`
# 并吐出一大段帮助文本，而复制粘贴时顺手带上空格/换行是非常常见的。
normalize_hostname() {
    local value="$1"
    local stripped

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [[ -z "$value" ]]; then
        return 1
    fi

    # 直接从浏览器地址栏粘贴 "https://ssh.example.com/" 是最常见的"错误"输入。
    # cloudflared 自己其实也接受带 scheme 的写法，没必要把用户打回去重输：
    # 自动剥掉 scheme 和路径/查询/片段，只保留主机名，并明确告知。
    stripped="$value"
    if [[ "$stripped" =~ ^[A-Za-z][A-Za-z0-9+.-]*:// ]]; then
        stripped="${stripped#*://}"
    fi
    stripped="${stripped%%[/?#]*}"
    if [[ -z "$stripped" ]]; then
        return 1
    fi
    if [[ "$stripped" != "$value" ]]; then
        echo "提示：已从 '$value' 中提取主机名：$stripped"
        value="$stripped"
    fi

    # 中间的空白同样会让 cloudflared 解析失败。
    if [[ "$value" == *[[:space:]]* ]]; then
        return 1
    fi
    # 以 '-' 开头的输入会被下游当成命令行选项。
    if [[ "$value" == -* ]]; then
        return 1
    fi
    # '@' 会让该值被解析成用户信息而不是主机名（'/' '?' '#' 已在上面剥掉）。
    if [[ "$value" == *@* ]]; then
        return 1
    fi

    TUNNEL_HOSTNAME="$value"
}

# 循环直到获得一个可用的隧道地址，行为与下面的端口号处理保持一致。
hostname_eof=false
while true; do
    if [[ -z "$TUNNEL_HOSTNAME" ]]; then
        if ! IFS= read -r -p "请输入隧道地址 (hostname): " TUNNEL_HOSTNAME; then
            # 输入流提前结束（如管道输入末尾无换行符）时保留已读取到的内容。
            hostname_eof=true
            echo
        fi
    fi

    raw_hostname="$TUNNEL_HOSTNAME"
    if ! normalize_hostname "$TUNNEL_HOSTNAME"; then
        if [[ -z "${TUNNEL_HOSTNAME//[[:space:]]/}" ]]; then
            echo "错误：隧道地址不能为空。" >&2
        else
            echo "错误：隧道地址 '$raw_hostname' 含有空格或非法字符，请重新输入。" >&2
        fi
        # 输入流已经关闭，无法再次询问。
        if [[ "$hostname_eof" == true ]]; then
            exit 1
        fi
        TUNNEL_HOSTNAME=""
        continue
    fi
    break
done

# -- 获取并验证 Port --
PORT="${2:-}"
if [[ -n "$PORT" ]]; then
    echo "已从命令行参数获取本地监听端口: $PORT"
fi

normalize_port() {
    local value="$1"
    local number

    # 与主机名一样容忍首尾空白（" 2222 " 这种粘贴结果没必要打回去）。
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    # 一条正则同时完成：只允许十进制数字、剥掉前导零、去零后最多 5 位
    # （顺带挡掉会让 $(( )) 溢出的超长数字）。原先第二条 [[ =~ ]] 不带 || return，
    # 一旦在 if 之外调用本函数就会被 set -e 直接终止脚本。
    [[ "$value" =~ ^0*([0-9]{1,5})$ ]] || return 1
    number=$((10#${BASH_REMATCH[1]}))
    (( number >= 1 && number <= 65535 )) || return 1
    PORT="$number"
}

# 循环直到获得一个有效的端口号。
# port_allow_default：只有"从未提供过端口"时，输入流结束才回落到默认端口。
# 用户明确给过端口却无效时，不应该悄悄换成另一个端口连上去。
port_allow_default=true
while true; do
    if [[ -z "$PORT" ]]; then
        if ! IFS= read -r -p "请输入本地监听端口 [$DEFAULT_PORT]: " PORT; then
            # 输入流提前结束（管道末尾缺少换行符，或用户直接按下 Ctrl-D）：
            # 已读取到的内容照常校验；什么都没读到就按提示采用默认端口。
            echo
            if [[ -z "$PORT" && "$port_allow_default" != true ]]; then
                echo "错误：未能读取端口号。" >&2
                exit 1
            fi
        fi
        PORT=${PORT:-$DEFAULT_PORT}
    fi

    raw_port="$PORT"
    if ! normalize_port "$PORT"; then
        echo "错误：端口号 '$raw_port' 必须是 1 到 65535 之间的十进制数字。" >&2
        PORT=""
        port_allow_default=false
        continue
    fi

    if (( PORT < 1024 )) && [[ $EUID -ne 0 ]]; then
        echo "提示：您选择的端口 '$PORT' 是一个周知端口。绑定到此端口通常需要管理员权限 (sudo)。"
    fi
    break
done

# 6. 执行最终命令
echo ""
echo "［已使用 '$CLOUDFLARED_BINARY' 执行连接命令，以下是程序的输出］"
echo "----------------------------------------------------"
exec "$CLOUDFLARED_BINARY" access tcp --listener "127.0.0.1:$PORT" --hostname "$TUNNEL_HOSTNAME"
