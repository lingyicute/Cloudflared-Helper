# Cloudflared-Helper

[简体中文](./README.md) | English

This is a powerful Bash script designed to simplify and automate the process of establishing TCP connections via [Cloudflare Tunnel](https://www.cloudflare.com/products/tunnel/). It is particularly useful for users who frequently need to connect to remote desktops, SSH, or other TCP services, saving you from the hassle of remembering and manually typing lengthy commands.

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

## Core Features

This script is more than just a simple command alias; it is a smart, user-friendly assistant tool.

* **Smart Architecture Detection**: Automatically identifies your current system architecture (`x86_64`, `aarch64`, `arm`) and matches it with the correct `cloudflared` binary file.
* **Automated Binary Management**:
    * **Auto-Download**: If the required `cloudflared` binary is missing, it will prompt and ask if you'd like to download the latest version from the official GitHub repository.
    * **Auto-Permissioning**: Automatically grants execution permissions (`chmod +x`) to the `cloudflared` file, resolving common "permission denied" issues.
* **Flexible Operation Modes**:
    * **Interactive Mode**: Run the script directly, and it will guide you through a clear Q&A to input the required hostname and port. Perfect for beginners or infrequent connections.
    * **Parameter Mode**: Append the hostname and port directly after the command, allowing advanced users to execute it quickly or integrate it into other scripts.
* **Robust Input Validation**:
    * Strictly validates the port number to ensure it is a valid integer between `1` and `65535`.
    * Thoughtfully issues a warning if you select a port below 1024 (well-known ports), reminding you that administrator privileges (`sudo`) might be required.
* **Clear Help & Error Messages**:
    * Provides standard `-h` or `--help` documentation for quick reference at any time.
    * Delivers clear status feedback or error messages at every step of execution, so you always know exactly what is happening.

## Download

You can download the latest packaged release directly from the links below. These files are automatically built by GitHub Actions and include both the helper script and the `cloudflared` binary for the corresponding architecture. Just download, extract, and run.

| Architecture | Description | Download Link |
| :--- | :--- | :--- |
| **x86_64 / amd64** | For most 64-bit desktops and servers (Intel/AMD) | [**⬇️ Download**](https://github.com/lingyicute/Cloudflared-Helper/releases/latest/download/cf-helper-amd64.tar.gz) |
| **aarch64 / arm64** | For 64-bit ARM devices (e.g., Raspberry Pi 3/4/5, M1/M2/M3 Mac) | [**⬇️ Download**](https://github.com/lingyicute/Cloudflared-Helper/releases/latest/download/cf-helper-arm64.tar.gz) |
| **arm / armv7l** | For 32-bit ARM devices (e.g., older Raspberry Pi models) | [**⬇️ Download**](https://github.com/lingyicute/Cloudflared-Helper/releases/latest/download/cf-helper-arm.tar.gz) |

You can also visit the [**Releases Page**](https://github.com/lingyicute/Cloudflared-Helper/releases).

## Requirements

* `bash`
* `curl` or `wget` (Only required if auto-downloading `cloudflared`)

## How to Use

#### 1. Get the Script

Download the `cf-helper.sh` file to your computer. It is recommended to place it in the same directory as your `cloudflared` binary.

#### 2. Grant Execution Permissions

Open your terminal, navigate to the directory containing the script, and run the following command:

```bash
chmod +x cf-helper.sh
```

#### 3. Run the Script

Now you can use it in the following ways:

* **Method 1: Interactive Mode (Recommended)**

    Run the script directly, and it will guide you through each step.

    ```bash
    ./cf-helper.sh
    Please enter the tunnel hostname: your-tunnel.example.com
    Please enter the local listening port [21128]:
    ```

* **Method 2: Parameter Mode (Fast)**

    Provide all necessary parameters directly after the command.

    ```bash
    # Usage: ./cf-helper.sh [HOSTNAME] [PORT]
    
    # Example:
    ./cf-helper.sh your-tunnel.example.com 21128
    ```

* **Method 3: Get Help**

    View all available commands and instructions.
    ```bash
    ./cf-helper.sh --help
    ```

## License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**.

You are free to:

* **Share** — Copy and redistribute the material in any medium or format.
* **Adapt** — Remix, transform, and build upon the material.

Under the following terms:

* **Attribution** — You must give appropriate credit, provide a link to the license, and indicate if changes were made.
* **ShareAlike** — If you remix, transform, or build upon the material, you must distribute your contributions under the same license as the original.
* **Source Code Availability** — If you run a modified version of this program on a network server, you must offer all users the opportunity to access the corresponding source code.

For more details, please see the [full AGPL-3.0 License text](https://www.gnu.org/licenses/agpl-3.0.html).
