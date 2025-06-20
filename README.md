# Cloudflared 连接助手 (cf-helper)

这是一个功能强大的 Bash 脚本，旨在简化并自动化通过 [Cloudflare Tunnel](https://www.cloudflare.com/products/tunnel/) 建立 TCP 连接的过程。它特别适合需要频繁连接远程桌面、SSH 或其他 TCP 服务的用户，可以免去记忆和手动输入冗长命令的麻烦。

[![授权协议: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

## 核心功能

这个脚本不仅仅是一个简单的命令别名，它是一个智能的、用户友好的辅助工具。

* **智能架构检测**: 自动识别您当前的系统架构（`x86_64`, `aarch64`, `arm`），并匹配正确的 `cloudflared` 二进制文件名。
* **二进制文件自动管理**:
    * **自动下载**: 当脚本所需的 `cloudflared` 文件不存在时，它会提示并询问是否从 GitHub 官方仓库下载最新版本。
    * **自动授权**: 自动为 `cloudflared` 文件添加执行权限 (`chmod +x`)，解决“权限不足”的常见问题。
* **灵活的操作模式**:
    * **交互模式**: 直接运行脚本，程序将通过清晰的问答形式引导您输入连接所需的主机名和端口号，非常适合新手或不常用的连接。
    * **参数模式**: 在命令后直接附加主机名和端口号，方便熟练用户快速执行或集成到其他脚本中。
* **强大的输入验证**:
    * 严格检查端口号，确保其为 `1` 到 `65535` 范围内的有效数字。
    * 当您选择的端口低于 1024（周知端口）时，会贴心地发出警告，提示您可能需要管理员权限 (`sudo`)。
* **清晰的帮助与错误提示**:
    * 提供标准的 `-h` 或 `--help` 帮助信息，方便随时查阅。
    * 在执行的每一步都提供明确的状态反馈或错误信息，让您清楚地知道发生了什么。

## 下载

您可以从下方的链接直接下载最新版本的打包发行版。这些文件由 GitHub Actions 自动构建，包含了助手脚本和对应架构的 `cloudflared` 程序。下载后解压即可使用。

| 架构 | 描述 | 下载链接 |
| :--- | :--- | :--- |
| **x86_64 / amd64** | 适用于绝大多数64位桌面电脑和服务器 (Intel/AMD) | [**⬇️ 下载**](https://github.com/lingyicute/Cloudflared-Helper/releases/latest/download/cf-helper-amd64.tar.gz) |
| **aarch64 / arm64** | 适用于64位ARM设备 (如 树莓派3/4/5, M1/M2/M3 Mac 等) | [**⬇️ 下载**](https://github.com/lingyicute/Cloudflared-Helper/releases/latest/download/cf-helper-arm64.tar.gz) |
| **arm / armv7l** | 适用于32位ARM设备 (如 旧版树莓派) | [**⬇️ 下载**](https://github.com/lingyicute/Cloudflared-Helper/releases/latest/download/cf-helper-arm.tar.gz) |

您也可以访问 [**Releases 页面**](https://github.com/lingyicute/Cloudflared-Helper/releases)。

## 环境要求

* `bash`
* `curl` 或 `wget` (仅在需要自动下载 `cloudflared` 时需要)

## 如何使用

#### 1. 获取脚本

将 `cf-helper.sh` 文件下载到您的电脑上，并建议将其与您的 `cloudflared` 二进制文件放在同一个目录中。

#### 2. 授予执行权限

打开终端，进入脚本所在的目录，然后运行以下命令：

```bash
chmod +x cf-helper.sh
```

#### 3. 运行脚本

现在您可以通过以下几种方式来使用它：

* **方式一：交互模式 (推荐)**

    直接运行脚本，它会引导您完成每一步操作。

    ```bash
    ./cf-helper.sh
    请输入隧道地址 (hostname): your-tunnel.example.com
    请输入本地监听端口 [21128]:
    ```

* **方式二：参数模式 (快速)**

    直接在命令后提供所有必需的参数。

    ```bash
    # 用法: ./cf-helper.sh [HOSTNAME] [PORT]
    
    # 示例:
    ./cf-helper.sh your-tunnel.example.com 21128
    ```

* **方式三：获取帮助**

    查看所有可用的命令和说明。
    ```bash
    ./cf-helper.sh --help
    ```

## 授权协议

本项目基于 **GNU Affero General Public License v3.0 (AGPL-3.0)** 授权。

您可以自由地：

* **共享** — 在任何媒介以任何形式复制、发行本作品。
* **演绎** — 修改、转换或以本作品为基础进行创作。

惟须遵守下列条件：

* **署名** — 您必须给出适当的署名，提供指向本许可协议的链接，同时标明是否对原始作品作了修改。
* **以相同方式共享** — 如果您再混合、转换或者基于本作品进行创作，您必须基于与原先许可协议相同的许可协议分发您贡献的作品。
* **源代码提供** — 如果您在网络服务器上运行本程序的修改版本，您必须向所有用户提供访问相应源代码的机会。

更多详情，请查阅 [AGPL-3.0 许可证全文](https://www.gnu.org/licenses/agpl-3.0.html)。
