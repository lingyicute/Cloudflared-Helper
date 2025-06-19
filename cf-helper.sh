#!/bin/bash

# 1. 确定当前设备架构，并寻找对应的 cloudflared 二进制文件
ARCH=$(uname -m)
CLOUDFLARED_BINARY=""

# 根据不同的架构名称，设置对应的二进制文件名
if [[ "$ARCH" == "x86_64" ]]; then
    CLOUDFLARED_BINARY="./cloudflared-linux-amd64"
elif [[ "$ARCH" == "aarch64" ]]; then
    CLOUDFLARED_BINARY="./cloudflared-linux-arm64"
elif [[ "$ARCH" == "arm" || "$ARCH" == "armv7l" ]]; then
    CLOUDFLARED_BINARY="./cloudflared-linux-arm"
else
    # 如果没有匹配的，提示用户并退出
    echo "错误：无法为当前架构 '$ARCH' 确定兼容的 cloudflared 二进制文件。"
    echo "请确保一个有效的 cloudflared 二进制文件（例如 cloudflared-linux-amd64）与本脚本位于同一目录下。"
    exit 1
fi

# 检查对应的二进制文件是否存在
if [ ! -f "$CLOUDFLARED_BINARY" ]; then
    echo "错误：未在当前目录中找到所需的二进制文件 '$CLOUDFLARED_BINARY'。"
    exit 1
fi

echo "脚本已启动，将使用 '$CLOUDFLARED_BINARY' 执行连接。"
echo ""

# 2. 交互式输入端口号，提供默认值
read -p "请输入端口［21128］： " PORT
# 如果用户直接回车，PORT 变量为空，此时使用默认值 21128
PORT=${PORT:-21128}

# 3. 交互式输入隧道地址
read -p "请输入隧道地址： " HOSTNAME

# 检查隧道地址是否为空
if [ -z "$HOSTNAME" ]; then
    echo "错误：隧道地址不能为空。"
    exit 1
fi

# 4. 执行命令并呈现输出
echo ""
echo "［已使用 $CLOUDFLARED_BINARY 执行连接命令，以下是程序的输出］"
echo "----------------------------------------------------"

# 执行最终的命令
exec $CLOUDFLARED_BINARY access tcp --listener 127.0.0.1:$PORT --hostname $HOSTNAME
