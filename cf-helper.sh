#!/bin/bash

# ==============================================================================
#  cf-helper.sh - Cloudflared 连接助手 (v3.4)
#  - 增加了对端口号的有效性验证 (1-65535)
#  - 增加了对周知端口 (< 1024) 的警告
# ==============================================================================

set -e
set -u

# 0. 显示帮助信息
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Cloudflared 连接助手 (cf-helper.sh)"
    echo ""
    echo "用法: ./cf-helper.sh [HOSTNAME] [PORT]"
    echo ""
    echo "参数:"
    echo "  HOSTNAME   (可选) 您要连接的隧道地址 (e.g., tunnel.example.com)。"
    echo "  PORT       (可选) 本地监听的TCP端口 (1-65535)。如果未提供，默认为 21128。"
    echo ""
    echo "如果未提供任何参数，脚本将以交互模式启动，依次询问所需信息。"
    exit 0
fi

# 1. 确定当前设备架构
ARCH=$(uname -m)
CLOUDFLARED_BINARY=""
KNOWN_ARCH=true

# 尝试匹配已知架构
if [[ "$ARCH" == "x86_64" ]]; then
    CLOUDFLARED_BINARY="cloudflared-linux-amd64"
elif [[ "$ARCH" == "aarch64" ]]; then
    CLOUDFLARED_BINARY="cloudflared-linux-arm64"
elif [[ "$ARCH" == "arm" || "$ARCH" == "armv7l" ]]; then
    CLOUDFLARED_BINARY="cloudflared-linux-arm"
else
    KNOWN_ARCH=false
fi

# 2. 根据架构类型处理二进制文件
if [ "$KNOWN_ARCH" = true ]; then
    if [ ! -f "$CLOUDFLARED_BINARY" ]; then
        echo "提示：为架构 '$ARCH' 设计的二进制文件 '$CLOUDFLARED_BINARY' 不存在。"
        read -p "是否要自动从 GitHub 下载最新版本？ (y/n): " choice

        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            DOWNLOAD_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/$CLOUDFLARED_BINARY"
            echo "正在从 $DOWNLOAD_URL 下载..."

            if command -v curl &> /dev/null; then
                curl -L --progress-bar -o "$CLOUDFLARED_BINARY" "$DOWNLOAD_URL"
            elif command -v wget &> /dev/null; then
                wget -q --show-progress -O "$CLOUDFLARED_BINARY" "$DOWNLOAD_URL"
            else
                echo "错误：需要 curl 或 wget 来下载文件，但两者都未安装。" >&2
                exit 1
            fi

            if [ ! -f "$CLOUDFLARED_BINARY" ]; then
                echo "错误：下载失败。请检查网络连接或下载链接。" >&2
                exit 1
            fi
            echo "下载成功。"
        else
            echo "操作已取消。" >&2
            exit 1
        fi
    fi
else
    echo "提示：无法为您的未知架构 '$ARCH' 自动匹配常规版本。"
    echo "正在当前目录中查找用户手动提供的二进制文件 (名称以 'cloudflared' 开头)..."
    
    mapfile -d '' CANDIDATES < <(find . -maxdepth 1 -name 'cloudflared*' -type f -print0)

    if [ "${#CANDIDATES[@]}" -eq 1 ]; then
        CLOUDFLARED_BINARY="${CANDIDATES[0]}"
        echo "成功！已找到并选择二进制文件: $CLOUDFLARED_BINARY"
    elif [ "${#CANDIDATES[@]}" -gt 1 ]; then
        echo "错误：在当前目录中找到多个可能的 cloudflared 文件：" >&2
        printf '  %s\n' "${CANDIDATES[@]}"
        echo "请只保留一个，或修改脚本以指定要使用的文件。" >&2
        exit 1
    else
        echo "错误：未能在当前目录中找到任何以 'cloudflared' 开头的文件。" >&2
        echo "请从 https://github.com/cloudflare/cloudflared/releases 下载适用于您架构 '$ARCH' 的版本，并将其放置在本脚本所在的目录中。" >&2
        exit 1
    fi
fi

# 3. 最终检查并确保文件可执行
if [ -z "$CLOUDFLARED_BINARY" ] || [ ! -f "$CLOUDFLARED_BINARY" ]; then
   echo "严重错误：未能定位到可用的 cloudflared 二进制文件。" >&2
   exit 1
fi

if [ ! -x "$CLOUDFLARED_BINARY" ]; then
    echo "提示：文件 '$CLOUDFLARED_BINARY' 不是可执行文件，正在尝试添加权限..."
    chmod +x "$CLOUDFLARED_BINARY"
    if [ ! -x "$CLOUDFLARED_BINARY" ]; then
        echo "错误：无法为文件 '$CLOUDFLARED_BINARY' 设置可执行权限。请手动执行 'chmod +x $CLOUDFLARED_BINARY'。" >&2
        exit 1
    fi
fi

if [[ "$CLOUDFLARED_BINARY" != ./* && "$CLOUDFLARED_BINARY" != /* ]]; then
    CLOUDFLARED_BINARY="./$CLOUDFLARED_BINARY"
fi

echo ""
echo "脚本已启动，将使用 '$CLOUDFLARED_BINARY' 执行连接。"
echo ""

# 4. 获取并验证连接参数
# -- 获取 Hostname --
HOSTNAME="${1:-}"
if [ -z "$HOSTNAME" ]; then
    read -p "请输入隧道地址 (hostname): " HOSTNAME
else
    echo "已从命令行参数获取隧道地址: $HOSTNAME"
fi

if [ -z "$HOSTNAME" ]; then
    echo "错误：隧道地址不能为空。" >&2
    exit 1
fi

# -- 获取并验证 Port --
PORT="${2:-}" # 从命令行获取初始值
if [ -n "$PORT" ]; then
    echo "已从命令行参数获取本地监听端口: $PORT"
fi

# 循环直到获得一个有效的端口号
while true; do
    # 如果 PORT 变量为空 (来自命令行的值无效或尚未输入), 则提示用户输入
    if [ -z "$PORT" ]; then
        read -p "请输入本地监听端口 [21128]: " PORT
        PORT=${PORT:-21128} # 如果用户直接回车, 使用默认值
    fi

    # 验证1: 检查是否为纯数字
    if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        echo "错误：端口 '$PORT' 必须是一个有效的数字。" >&2
        PORT="" # 重置为空, 以便下次循环时重新提问
        continue
    fi

    # 验证2: 检查是否在 1-65535 范围内
    if (( PORT < 1 || PORT > 65535 )); then
        echo "错误：端口号 '$PORT' 必须在 1 到 65535 之间。" >&2
        PORT="" # 重置为空
        continue
    fi

    # 验证3: 如果是周知端口 (<1024) 且当前用户非root, 则发出警告
    if (( PORT < 1024 )) && [[ $EUID -ne 0 ]]; then
        echo "提示：您选择的端口 '$PORT' 是一个周知端口。绑定到此端口通常需要管理员权限 (sudo)。"
    fi
    
    # 所有验证通过, 退出循环
    break
done


# 5. 执行最终命令
echo ""
echo "［已使用 '$CLOUDFLARED_BINARY' 执行连接命令，以下是程序的输出］"
echo "----------------------------------------------------"
exec "$CLOUDFLARED_BINARY" access tcp --listener 127.0.0.1:$PORT --hostname "$HOSTNAME"
