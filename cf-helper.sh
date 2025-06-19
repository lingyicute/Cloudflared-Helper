#!/bin/bash

# ==============================================================================
#  cf-helper.sh - Cloudflared 连接助手 (v3.1)
# ==============================================================================

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
    # 对于已知架构，如果文件不存在，则提供自动下载
    if [ ! -f "$CLOUDFLARED_BINARY" ]; then
        echo "提示：为架构 '$ARCH' 设计的二进制文件 '$CLOUDFLARED_BINARY' 不存在。"
        read -p "是否要自动从 GitHub 下载最新版本？ (y/n): " choice

        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            DOWNLOAD_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/$CLOUDFLARED_BINARY"
            echo "正在从 $DOWNLOAD_URL 下载..."

            if command -v curl &> /dev/null; then
                curl -L -o "$CLOUDFLARED_BINARY" "$DOWNLOAD_URL"
            elif command -v wget &> /dev/null; then
                wget -O "$CLOUDFLARED_BINARY" "$DOWNLOAD_URL"
            else
                echo "错误：需要 curl 或 wget 来下载文件，但两者都未安装。" >&2
                exit 1
            fi

            if [ $? -ne 0 ]; then
                echo "错误：下载失败。请检查网络连接。" >&2
                rm -f "$CLOUDFLARED_BINARY"
                exit 1
            fi
            echo "下载成功。"
        else
            echo "操作已取消。" >&2
            exit 1
        fi
    fi
else
    # 对于未知架构，扫描本地目录寻找用户提供的文件
    echo "提示：无法为您的未知架构 '$ARCH' 自动匹配常规版本。"
    echo "正在当前目录中查找用户手动提供的二进制文件 (名称以 'cloudflared' 开头)..."
    
    mapfile -d '' CANDIDATES < <(find . -maxdepth 1 -name 'cloudflared*' -type f -print0)

    if [ "${#CANDIDATES[@]}" -eq 1 ]; then
        # 从 find 的结果中提取文件名，它本身已包含 ./ 路径
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
# 此时，CLOUDFLARED_BINARY 变量必须有值且指向一个文件
if [ -z "$CLOUDFLARED_BINARY" ] || [ ! -f "$CLOUDFLARED_BINARY" ]; then
   echo "严重错误：未能定位到可用的 cloudflared 二进制文件。" >&2
   exit 1
fi

if [ ! -x "$CLOUDFLARED_BINARY" ]; then
    echo "提示：文件 '$CLOUDFLARED_BINARY' 不是可执行文件，正在尝试添加权限..."
    chmod +x "$CLOUDFLARED_BINARY"
    if [ $? -ne 0 ]; then
        echo "错误：无法为文件 '$CLOUDFLARED_BINARY' 设置可执行权限。请手动执行 'chmod +x $CLOUDFLARED_BINARY'。" >&2
        exit 1
    fi
fi

# 如果变量不包含路径，为其添加 ./ 前缀，确保执行的确定性
if [[ "$CLOUDFLARED_BINARY" != ./* && "$CLOUDFLARED_BINARY" != /* ]]; then
    CLOUDFLARED_BINARY="./$CLOUDFLARED_BINARY"
fi

echo ""
echo "脚本已启动，将使用 '$CLOUDFLARED_BINARY' 执行连接。"
echo ""

# 4. 交互式输入参数
read -p "请输入本地监听端口［21128］： " PORT
PORT=${PORT:-21128}

read -p "请输入隧道地址 (hostname)： " HOSTNAME
if [ -z "$HOSTNAME" ]; then
    echo "错误：隧道地址不能为空。" >&2
    exit 1
fi

# 5. 执行最终命令
echo ""
echo "［已使用 '$CLOUDFLARED_BINARY' 执行连接命令，以下是程序的输出］"
echo "----------------------------------------------------"
exec "$CLOUDFLARED_BINARY" access tcp --listener 127.0.0.1:$PORT --hostname $HOSTNAME
