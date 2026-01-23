# Armory

Automated development environment setup script for Debian-based Linux distributions. Armory installs and configures a comprehensive suite of development tools, modern CLI utilities, and shell enhancements.

## What It Installs

### Core Development Tools
- **LLVM/Clang Toolchain**: clang-18, clangd, clang-format, clang-tidy, lld, lldb
- **Build Essentials**: gcc, g++, make, autoconf, automake, libtool, pkg-config
- **Debugging & Analysis**: gdb, valgrind, cppcheck, cpplint
- **Version Control**: git, git-lfs

### Modern CLI Tools
- **Neovim**: Latest version from GitHub releases
- **Shell**: zsh with oh-my-zsh and custom foursight theme
- **System Monitor**: btop
- **File Listing**: eza (modern ls replacement)
- **Markdown Viewer**: glow
- **Search**: ripgrep
- **Session Manager**: tmux

### Development Platforms
- **Node.js**: LTS version
- **Rust**: Latest stable via rustup
- **Python**: Latest available Python 3.x with pip and venv
- **Docker**: docker.io, Docker Compose v2 (plugin), containerd

### Network & Utilities
- socat, ncat, net-tools, sshpass, bind9-dnsutils
- curl, wget, unzip, stow
- cowsay, fortune-mod

### Configurations
- Custom Neovim configuration from personal dotfiles
- Google's Python style guide (.pylintrc)
- Custom clang-format configuration (.clang-format)
- zsh-autosuggestions plugin
- Useful shell aliases (eza shortcuts, clang-18 defaults)
- Docker group membership for non-root docker usage

## Prerequisites

- Debian-based Linux distribution (Debian 12 "Bookworm" or Ubuntu)
- Root/sudo access
- Active internet connection
- **Important**: Review the script contents before execution - it modifies system configuration and installs packages

## Installation

### Quick Install (wget)

**⚠️ Security Warning**: Always review scripts before running them with sudo, especially when downloaded from the internet. The script makes system-wide changes and requires root privileges.

Download and inspect the script first:
```bash
wget https://raw.githubusercontent.com/f0ur3y3s/armory/main/armory.sh
cat armory.sh  # Review the script contents
chmod +x armory.sh
sudo ./armory.sh
```

Or download and run in one command (only if you trust the source):
```bash
wget -O - https://raw.githubusercontent.com/f0ur3y3s/armory/main/armory.sh | sudo bash
```
**Warning**: The one-liner above executes the script without review. Use at your own risk.

### Git Clone Method

1. Clone this repository:
```bash
git clone https://github.com/f0ur3y3s/armory.git
cd armory
```

2. Make the script executable:
```bash
chmod +x armory.sh
```

3. Run with sudo:
```bash
sudo ./armory.sh
```

The script will:
- Fix CD-ROM repository issues if present
- Add Debian backports repository
- Install all packages
- Set up user-specific configurations
- Download and install tools from GitHub releases

## Post-Installation

1. **Log out and log back in** for group membership changes (Docker) and shell changes to take effect
2. Start zsh: `zsh`
3. Open Neovim to trigger plugin installation: `nvim`

## Features

- **Idempotent**: Safe to run multiple times, skips already installed packages
- **User-aware**: Configures tools for the actual user, not root, even when run with sudo
- **Modern defaults**: clang-18 set as default compiler via update-alternatives
- **Backports enabled**: Access to newer packages from Debian backports

## Customization

The script pulls custom configurations from:
- Neovim config: `https://github.com/f0ur3y3s/nvim.git`
- Zsh theme: `https://github.com/f0ur3y3s/dotfiles`
- Clang-format: `https://github.com/f0ur3y3s/clang-barrc/blob/main/.clang-format`
- Pylintrc: `https://google.github.io/styleguide/pylintrc`

Fork and modify these URLs in `armory.sh` to use your own configurations.

## Notes

- The script requires root privileges to install system packages
- Estimated run time: 10-30 minutes depending on network speed and system
- Creates `~/.oh-my-zsh`, `~/.config/nvim`, `~/.pylintrc`, `~/.clang-format`, and modifies `~/.zshrc`
- Docker commands will work after logging out and back in (group membership)
