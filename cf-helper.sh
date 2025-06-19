#!/bin/bash

# ==============================================================================
#  cf-helper.sh - Cloudflared RDP 连接助手 (v2 - 带自动下载功能)
# ==============================================================================

# 1. 确定当前设备架构，并寻找对应的 cloudflared 二进制文件
ARCH=$(uname -m)
CLOUDFLARED_BINARY=""

# 根据不同的架构名称，设置对应的二进制文件名
if [[ "$ARCH" == "x86_64" ]]; then
    CLOUDFLARED_BINARY="cloudflared-linux-amd64"
elif [[ "$ARCH" == "aarch64" ]]; then
    CLOUDFLARED_BINARY="cloudflared-linux-arm64"
elif [[ "$ARCH" == "arm" || "$ARCH" == "armv7l" ]]; then
    CLOUDFLARED_BINARY="cloudflared-linux-arm"
else
    # 如果没有匹配的，提示用户并退出
    echo "错误：无法为当前架构 '$ARCH' 确定兼容的 cloudflared 二进制文件。"
    echo "请从 https://github.com/cloudflare/cloudflared/releases 手动下载。"
    exit 1
fi

# 2. 检查对应的二进制文件是否存在，如果不存在则尝试下载
if [ ! -f "$CLOUDFLARED_BINARY" ]; then
    echo "提示：在当前目录中未找到 '$CLOUDFLARED_BINARY'。"
    read -p "是否要自动从 GitHub 下载最新版本？ (y/n): " choice

    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        DOWNLOAD_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/$CLOUDFLARED_BINARY"
        echo "正在从 $DOWNLOAD_URL 下载..."

        # 检查系统中是否存在 curl 或 wget
        if command -v curl &> /dev/null; then
            curl -L -o "$CLOUDFLARED_BINARY" "$DOWNLOAD_URL"
        elif command -v wget &> /dev/null; then
            wget -O "$CLOUDFLARED_BINARY" "$DOWNLOAD_URL"
        else
            echo "错误：需要 curl 或 wget 来下载文件，但两者都未安装。"
            exit 1
        fi

        # 检查下载是否成功
        if [ $? -ne 0 ]; then
            echo "错误：下载失败。请检查您的网络连接或 URL 是否正确。"
            rm -f "$CLOUDFLARED_BINARY" # 清理不完整的文件
            exit 1
        fi

        echo "下载成功。"
        echo "正在为 '$CLOUDFLARED_BINARY' 添加可执行权限..."
        chmod +x "$CLOUDFLARED_BINARY"

        if [ $? -ne 0 ]; then
            echo "错误：无法为文件设置可执行权限。"
            exit 1
        fi

        echo "设置成功！脚本将继续执行。"
        echo ""
    else
        echo "操作已取消。请将 '$CLOUDFLARED_BINARY' 放置于脚本所在目录后重试。"
        exit 1
    fi
fi

echo "脚本已启动，将使用 './$CLOUDFLARED_BINARY' 执行连接。"
echo ""

# 3. 交互式输入端口号，提供默认值
read -p "请输入本地监听端口［21128］： " PORT
# 如果用户直接回车，PORT 变量为空，此时使用默认值 21128
PORT=${PORT:-21128}

# 4. 交互式输入隧道地址
read -p "请输入隧道地址 (hostname)： " HOSTNAME

# 检查隧道地址是否为空
if [ -z "$HOSTNAME" ]; then
    echo "错误：隧道地址不能为空。"
    exit 1
fi

# 5. 执行命令并呈现输出
echo ""
echo "［已使用 ./$CLOUDFLARED_BINARY 执行连接命令，以下是程序的输出］"
echo "----------------------------------------------------"

# 执行最终的命令
# 注意：路径前添加了 ./ 以确保执行当前目录下的文件
exec "./$CLOUDFLARED_BINARY" access tcp --listener 127.0.0.1:$PORT --hostname $HOSTNAME
