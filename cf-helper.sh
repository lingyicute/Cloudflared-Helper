#!/bin/bash

# ==============================================================================
#  cf-helper.sh - Cloudflared 连接助手 (v3.5)
#  - 支持 Linux 和 macOS 的 cloudflared 官方发行包
#  - 二进制文件始终相对于脚本目录查找/下载
#  - 增加了对端口号的有效性验证 (1-65535)
#  - 增加了对周知端口 (< 1024) 的警告
# ==============================================================================

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

# 1. 确定脚本目录。不要依赖调用脚本时的当前工作目录
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P) || {
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

case "${OS}:${ARCH}" in
    Linux:x86_64|Linux:amd64)
        CLOUDFLARED_BINARY="$SCRIPT_DIR/cloudflared-linux-amd64"
        CLOUDFLARED_ASSET="cloudflared-linux-amd64"
        KNOWN_PLATFORM=true
        ;;
    Linux:aarch64|Linux:arm64)
        CLOUDFLARED_BINARY="$SCRIPT_DIR/cloudflared-linux-arm64"
        CLOUDFLARED_ASSET="cloudflared-linux-arm64"
        KNOWN_PLATFORM=true
        ;;
    Linux:arm|Linux:armv7l|Linux:armhf)
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

# 下载到临时文件后再原子替换目标，避免中断后留下一个看似可用的残缺文件
download_file() {
    local url="$1"
    local destination="$2"
    local tmp_file

    if ! tmp_file=$(mktemp "${destination}.tmp.XXXXXX"); then
        echo "错误：无法在目标目录创建临时文件：$destination" >&2
        return 1
    fi

    if command -v curl >/dev/null 2>&1; then
        if ! curl --fail --location --show-error --retry 3 --connect-timeout 15 \
            --output "$tmp_file" "$url"; then
            rm -f "$tmp_file"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget --tries=3 --timeout=15 --output-document="$tmp_file" "$url"; then
            rm -f "$tmp_file"
            return 1
        fi
    else
        echo "错误：需要 curl 或 wget 来下载文件，但两者都未安装。" >&2
        rm -f "$tmp_file"
        return 1
    fi

    if [[ ! -s "$tmp_file" ]]; then
        echo "错误：下载结果为空。" >&2
        rm -f "$tmp_file"
        return 1
    fi

    if ! mv -f "$tmp_file" "$destination"; then
        echo "错误：无法将下载结果写入 '$destination'。" >&2
        rm -f "$tmp_file"
        return 1
    fi
}

# 3. 根据架构类型处理二进制文件
if [[ "$KNOWN_PLATFORM" == true ]]; then
    if [[ ! -f "$CLOUDFLARED_BINARY" ]]; then
        echo "提示：为 '$OS/$ARCH' 设计的二进制文件不存在：$(basename "$CLOUDFLARED_BINARY")"
        if ! IFS= read -r -p "是否要自动从 GitHub 下载最新版本？ (y/n): " choice; then
            choice="n"
            echo
        fi

        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
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
        echo "错误：无法为文件 '$CLOUDFLARED_BINARY' 设置可执行权限。请手动执行 'chmod +x "$CLOUDFLARED_BINARY"'。" >&2
        exit 1
    fi
fi

echo ""
echo "脚本已启动，将使用 '$CLOUDFLARED_BINARY' 执行连接。"
echo ""

# 5. 获取并验证连接参数
# -- 获取 Hostname --
HOSTNAME="${1:-}"
if [[ -z "$HOSTNAME" ]]; then
    if ! IFS= read -r -p "请输入隧道地址 (hostname): " HOSTNAME; then
        echo "错误：未能读取隧道地址。" >&2
        exit 1
    fi
else
    echo "已从命令行参数获取隧道地址: $HOSTNAME"
fi

if [[ -z "$HOSTNAME" ]]; then
    echo "错误：隧道地址不能为空。" >&2
    exit 1
fi

# -- 获取并验证 Port --
PORT="${2:-}"
if [[ -n "$PORT" ]]; then
    echo "已从命令行参数获取本地监听端口: $PORT"
fi

normalize_port() {
    local value="$1"
    local number

    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    [[ "$value" =~ ^0*([0-9]+)$ ]]
    value="${BASH_REMATCH[1]}"
    (( ${#value} <= 5 )) || return 1

    number=$((10#$value))
    (( number >= 1 && number <= 65535 )) || return 1
    PORT="$number"
}

# 循环直到获得一个有效的端口号。
while true; do
    if [[ -z "$PORT" ]]; then
        if ! IFS= read -r -p "请输入本地监听端口 [$DEFAULT_PORT]: " PORT; then
            echo "错误：未能读取端口号。" >&2
            exit 1
        fi
        PORT=${PORT:-$DEFAULT_PORT}
    fi

    raw_port="$PORT"
    if ! normalize_port "$PORT"; then
        echo "错误：端口号 '$raw_port' 必须是 1 到 65535 之间的十进制数字。" >&2
        PORT=""
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
exec "$CLOUDFLARED_BINARY" access tcp --listener "127.0.0.1:$PORT" --hostname "$HOSTNAME"
