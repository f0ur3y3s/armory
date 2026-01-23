#!/bin/bash

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)." >&2
    exit 1
fi

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Create log file
LOG_FILE="/tmp/armory-install.log"
exec 3>&1 4>&2  # Save stdout and stderr
echo "Installation started at $(date)" > "$LOG_FILE"

# Progress bar function
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))

    printf "\r${CYAN}["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' ' '
    printf "] ${BOLD}%3d%%${NC} ${BLUE}(%d/%d)${NC}" "$percentage" "$current" "$total"
}

# Logging wrapper function
log_output() {
    "$@" >> "$LOG_FILE" 2>&1
}

# Available packages - some may need alternative sources on Debian
PACKAGES=(
    # Core utilities
    "git" "git-lfs" "curl" "wget" "tmux" "build-essential" "ripgrep" "zsh" "unzip" "stow"
    # LLVM/Clang toolchain (latest version)
    "llvm-18" "llvm-18-dev" "llvm-18-tools" "clang-18" "clangd-18" "clang-format-18" "clang-tidy-18"
    "lld-18" "lldb-18"
    # Development tools
    "gdb" "valgrind" "autoconf" "automake" "libtool" "pkg-config"
    # C/C++ analysis tools
    "cppcheck" "cpplint"
    # Docker
    "docker.io" "containerd"
    # Network tools
    "socat" "ncat" "net-tools" "sshpass" "bind9-dnsutils"
    # Terminal utilities
    "cowsay" "fortune-mod" "eza" "glow"
    # Smart cat function prerequisites
    "vim-common" "jq" "bat"
)
# Note: neovim, btop, and zsh-autosuggestions need special handling

if command -v apt &>/dev/null; then
    PKG_MANAGER="apt"
    UPDATE_CMD="apt update"
    INSTALL_CMD="apt install -y"
else
    echo "Unsupported package manager. Exiting."
    exit 1
fi

echo ""
echo -e "${CYAN}${BOLD}============================================${NC}"
echo -e "${CYAN}${BOLD}   Armory - Development Environment Setup${NC}"
echo -e "${CYAN}${BOLD}============================================${NC}"
echo ""

# Fix CD-ROM repository issue first
if grep -q "cdrom:" /etc/apt/sources.list 2>/dev/null; then
    echo -e "${YELLOW}Fixing repository configuration...${NC}"
    sed -i 's/^deb cdrom:/#deb cdrom:/' /etc/apt/sources.list
fi

echo -ne "${BLUE}Updating package list...${NC}"
log_output $UPDATE_CMD
echo -e " ${GREEN}✓ Done${NC}"

# Handle Debian-specific package installations
# Add backports for newer packages
if ! grep -q "bookworm-backports" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
    echo -ne "${BLUE}Adding Debian backports repository...${NC}"
    echo "deb http://deb.debian.org/debian bookworm-backports main" >> /etc/apt/sources.list.d/backports.list
    log_output $UPDATE_CMD
    echo -e " ${GREEN}✓ Done${NC}"
fi

# For Python 3.13 on Debian, we'll compile from source or use alternative methods
# For now, we'll use the available Python version
PYTHON_PKG=$(apt list --available python3.* 2>/dev/null | grep -E "python3\.[0-9]+/" | sort -V | tail -1 | cut -d'/' -f1 | cut -d' ' -f1)
if [[ -n "$PYTHON_PKG" ]]; then
    PACKAGES+=("$PYTHON_PKG" "${PYTHON_PKG}-pip" "${PYTHON_PKG}-venv")
fi

# Install packages
echo ""
echo -e "${MAGENTA}${BOLD}Installing system packages...${NC}"
TOTAL_PACKAGES=${#PACKAGES[@]}
CURRENT=0

for package in "${PACKAGES[@]}"; do
    CURRENT=$((CURRENT + 1))
    show_progress $CURRENT $TOTAL_PACKAGES
    if ! dpkg -l 2>/dev/null | grep -q "^ii  $package "; then
        log_output $INSTALL_CMD "$package"
    fi
done
echo ""  # New line after progress bar
echo -e "${GREEN}✓ System packages installed${NC}"

# Install latest Neovim from GitHub
if ! command -v nvim &>/dev/null || [[ $(nvim --version 2>/dev/null | head -1 | grep -o '0\.[0-9]\+' | head -1) < "0.11" ]]; then
    echo -ne "${BLUE}Installing Neovim...${NC}"
    NVIM_VERSION=$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')

    if [[ -z "$NVIM_VERSION" ]]; then
        echo -e " ${RED}✗ Failed (couldn't fetch version)${NC}"
    else
        NVIM_URL="https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-linux-x86_64.tar.gz"

        cd /tmp
        if curl -fL "$NVIM_URL" -o nvim-linux-x86_64.tar.gz 2>> "$LOG_FILE"; then
            if file nvim-linux-x86_64.tar.gz | grep -q "gzip compressed data"; then
                tar xzf nvim-linux-x86_64.tar.gz 2>> "$LOG_FILE"
                rm -rf /usr/local/nvim-linux-x86_64
                mv nvim-linux-x86_64 /usr/local/
                ln -sf /usr/local/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
                echo -e " ${GREEN}✓ Done (v${NVIM_VERSION})${NC}"
            else
                echo -e " ${RED}✗ Failed (invalid download)${NC}"
            fi
        else
            echo -e " ${RED}✗ Failed (download error)${NC}"
        fi

        rm -f nvim-linux-x86_64.tar.gz
        cd /
    fi
else
    echo -e "${GREEN}✓ Neovim already installed${NC}"
fi

# Get the actual user (not root) for user-specific operations
ACTUAL_USER=${SUDO_USER:-$USER}
ACTUAL_HOME=$(eval echo ~$ACTUAL_USER)

echo ""
echo -e "${CYAN}${BOLD}Configuring environment for: ${MAGENTA}$ACTUAL_USER${NC}"

# Change shell to zsh for the actual user
if [[ $(getent passwd "$ACTUAL_USER" | cut -d: -f7) != "$(which zsh)" ]]; then
    echo -ne "${BLUE}Setting default shell to zsh...${NC}"
    chsh -s "$(which zsh)" "$ACTUAL_USER" 2>> "$LOG_FILE"
    echo -e " ${GREEN}✓ Done${NC}"
fi

# Install oh-my-zsh as the actual user
if [[ ! -d "$ACTUAL_HOME/.oh-my-zsh" ]]; then
    echo -ne "${BLUE}Installing oh-my-zsh...${NC}"
    sudo -u "$ACTUAL_USER" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended >> "$LOG_FILE" 2>&1
    echo -e " ${GREEN}✓ Done${NC}"
fi

# Get custom zsh theme
FOURSIGHT_URL="https://raw.githubusercontent.com/f0ur3y3s/dotfiles/refs/heads/main/omzsh/.oh-my-zsh/custom/themes/foursight.zsh-theme"
TARGET_DIR="$ACTUAL_HOME/.oh-my-zsh/custom/themes"
FOURSIGHT_FILENAME=$(basename "$FOURSIGHT_URL")

echo -ne "${BLUE}Installing custom zsh theme...${NC}"
sudo -u "$ACTUAL_USER" mkdir -p "$TARGET_DIR"
sudo -u "$ACTUAL_USER" curl -so "$TARGET_DIR/$FOURSIGHT_FILENAME" "$FOURSIGHT_URL"

if [[ -f "$ACTUAL_HOME/.zshrc" ]]; then
    sudo -u "$ACTUAL_USER" sed -i 's/ZSH_THEME=".*"/ZSH_THEME="foursight"/' "$ACTUAL_HOME/.zshrc"
fi
echo -e " ${GREEN}✓ Done${NC}"

# Install zsh-autosuggestions
ZSH_AUTOSUGGESTIONS_DIR="$ACTUAL_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
if [[ ! -d "$ZSH_AUTOSUGGESTIONS_DIR" ]]; then
    echo -ne "${BLUE}Installing zsh-autosuggestions...${NC}"
    sudo -u "$ACTUAL_USER" git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_AUTOSUGGESTIONS_DIR" >> "$LOG_FILE" 2>&1

    if [[ -f "$ACTUAL_HOME/.zshrc" ]] && ! grep -q "zsh-autosuggestions" "$ACTUAL_HOME/.zshrc"; then
        sudo -u "$ACTUAL_USER" sed -i 's/^plugins=(\(.*\))/plugins=(\1 zsh-autosuggestions)/' "$ACTUAL_HOME/.zshrc"
    fi
    echo -e " ${GREEN}✓ Done${NC}"
fi

# Setup Neovim config
NVIM_CONFIG_DIR="$ACTUAL_HOME/.config/nvim"
NVIM_REPO="https://github.com/f0ur3y3s/nvim.git"

if [[ ! -d "$NVIM_CONFIG_DIR" ]]; then
    echo -ne "${BLUE}Setting up Neovim configuration...${NC}"
    sudo -u "$ACTUAL_USER" mkdir -p "$ACTUAL_HOME/.config"
    sudo -u "$ACTUAL_USER" git clone "$NVIM_REPO" "$NVIM_CONFIG_DIR" >> "$LOG_FILE" 2>&1
    echo -e " ${GREEN}✓ Done${NC}"
fi

# Download Google's pylintrc
if [[ ! -f "$ACTUAL_HOME/.pylintrc" ]]; then
    echo -ne "${BLUE}Downloading pylintrc...${NC}"
    sudo -u "$ACTUAL_USER" curl -so "$ACTUAL_HOME/.pylintrc" "https://google.github.io/styleguide/pylintrc"
    echo -e " ${GREEN}✓ Done${NC}"
fi

# Download custom .clang-format
if [[ ! -f "$ACTUAL_HOME/.clang-format" ]]; then
    echo -ne "${BLUE}Downloading .clang-format...${NC}"
    sudo -u "$ACTUAL_USER" curl -so "$ACTUAL_HOME/.clang-format" "https://raw.githubusercontent.com/f0ur3y3s/clang-barrc/main/.clang-format"
    echo -e " ${GREEN}✓ Done${NC}"
fi

# Install GEF (GDB Enhanced Features)
if [[ ! -f "$ACTUAL_HOME/.gdbinit-gef.py" ]]; then
    echo -ne "${BLUE}Installing GEF for GDB...${NC}"
    sudo -u "$ACTUAL_USER" bash -c "curl -so $ACTUAL_HOME/.gdbinit-gef.py https://gef.blah.cat/py" >> "$LOG_FILE" 2>&1
    if [[ ! -f "$ACTUAL_HOME/.gdbinit" ]] || ! grep -q "gdbinit-gef.py" "$ACTUAL_HOME/.gdbinit"; then
        sudo -u "$ACTUAL_USER" bash -c "echo 'source ~/.gdbinit-gef.py' >> $ACTUAL_HOME/.gdbinit"
    fi
    echo -e " ${GREEN}✓ Done${NC}"
fi

# Install Node.js (often needed for Neovim plugins)
if ! command -v node &>/dev/null; then
    echo -ne "${BLUE}Installing Node.js...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - >> "$LOG_FILE" 2>&1
    log_output $INSTALL_CMD nodejs
    echo -e " ${GREEN}✓ Done${NC}"
fi

# Install Rust (useful for various tools)
if ! command -v rustc &>/dev/null; then
    echo -ne "${BLUE}Installing Rust...${NC}"
    sudo -u "$ACTUAL_USER" curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sudo -u "$ACTUAL_USER" sh -s -- -y >> "$LOG_FILE" 2>&1
    export PATH="$ACTUAL_HOME/.cargo/bin:$PATH"
    echo -e " ${GREEN}✓ Done${NC}"
fi

# Setup Docker group for user
if command -v docker &>/dev/null; then
    if ! groups "$ACTUAL_USER" | grep -q docker; then
        echo -ne "${BLUE}Adding $ACTUAL_USER to docker group...${NC}"
        usermod -aG docker "$ACTUAL_USER"
        echo -e " ${GREEN}✓ Done${NC}"
    fi

    # Install Docker Compose v2 plugin
    if ! docker compose version &>/dev/null; then
        echo -ne "${BLUE}Installing Docker Compose v2...${NC}"
        DOCKER_CONFIG=${DOCKER_CONFIG:-/usr/local/lib/docker}
        mkdir -p $DOCKER_CONFIG/cli-plugins
        COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
        curl -SL "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-x86_64" -o $DOCKER_CONFIG/cli-plugins/docker-compose 2>> "$LOG_FILE"
        chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
        echo -e " ${GREEN}✓ Done (v${COMPOSE_VERSION})${NC}"
    fi
fi

# Install btop (system monitor)
if ! command -v btop &>/dev/null; then
    echo -ne "${BLUE}Installing btop...${NC}"
    # Try from backports first, fallback to manual installation
    if ! log_output $INSTALL_CMD -t bookworm-backports btop; then
        BTOP_URL=$(curl -s https://api.github.com/repos/aristocratos/btop/releases/latest | grep -o 'https://.*btop.*linux.*x86_64.*tbz' | head -1)
        if [[ -n "$BTOP_URL" ]]; then
            cd /tmp
            curl -L "$BTOP_URL" -o btop.tbz 2>> "$LOG_FILE"
            tar -xf btop.tbz >> "$LOG_FILE" 2>&1
            cd btop
            make install PREFIX=/usr/local >> "$LOG_FILE" 2>&1
            cd /
            rm -rf /tmp/btop*
        fi
    fi
    echo -e " ${GREEN}✓ Done${NC}"
fi

# Setup clang alternatives to use clang-18 as default
if command -v clang-18 &>/dev/null; then
    echo -ne "${BLUE}Setting clang-18 as default...${NC}"
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-18 100 \
        --slave /usr/bin/clang++ clang++ /usr/bin/clang++-18 \
        --slave /usr/bin/clangd clangd /usr/bin/clangd-18 \
        --slave /usr/bin/clang-format clang-format /usr/bin/clang-format-18 \
        --slave /usr/bin/clang-tidy clang-tidy /usr/bin/clang-tidy-18 \
        --slave /usr/bin/lldb lldb /usr/bin/lldb-18 \
        --slave /usr/bin/lld lld /usr/bin/lld-18 >> "$LOG_FILE" 2>&1 || true
    echo -e " ${GREEN}✓ Done${NC}"
fi

# Create some useful aliases in .zshrc if they don't exist
ZSHRC_FILE="$ACTUAL_HOME/.zshrc"
if [[ -f "$ZSHRC_FILE" ]]; then
    # Add aliases section if it doesn't exist
    if ! grep -q "# Custom aliases" "$ZSHRC_FILE"; then
        echo -ne "${BLUE}Adding shell aliases and functions...${NC}"
        sudo -u "$ACTUAL_USER" bash -c "cat >> '$ZSHRC_FILE' << 'EOF'

# Custom aliases
alias ll='eza -la --git --icons'
alias la='eza -a --git --icons'
alias ls='eza --git --icons'
alias lt='eza -la --tree --level=2 --git --icons'
alias clang='clang-18'
alias clang++='clang++-18'
EOF"
    fi

    # Add smart cat function if it doesn't exist
    if ! grep -q "# Smart cat function" "$ZSHRC_FILE"; then
        sudo -u "$ACTUAL_USER" bash -c "cat >> '$ZSHRC_FILE' << 'EOF'

# Smart cat function - switches tools based on file type
cat() {
    for file in \"\$@\"; do
        # Skip if it's a flag/option
        if [[ \"\$file\" == -* ]]; then
            command cat \"\$@\"
            return
        fi

        # Check if file exists
        if [[ ! -f \"\$file\" ]]; then
            command cat \"\$@\"
            return
        fi

        # Detect file type
        local mime_type=\$(file --mime-type -b \"\$file\")
        local extension=\"\${file##*.}\"

        # Route to appropriate tool
        case \"\$mime_type\" in
            application/octet-stream|application/x-executable|application/x-sharedlib)
                xxd \"\$file\"
                ;;
            */x-*|application/gzip|application/zip)
                xxd \"\$file\"
                ;;
            text/markdown)
                if command -v glow &> /dev/null; then
                    glow \"\$file\"
                else
                    command cat \"\$file\"
                fi
                ;;
            application/json)
                if command -v jq &> /dev/null; then
                    jq '.' \"\$file\"
                else
                    command cat \"\$file\"
                fi
                ;;
            text/*)
                if command -v bat &> /dev/null; then
                    bat \"\$file\"
                else
                    command cat \"\$file\"
                fi
                ;;
            *)
                # Check by extension as fallback
                case \"\$extension\" in
                    md|markdown)
                        glow \"\$file\" 2>/dev/null || command cat \"\$file\"
                        ;;
                    json)
                        jq '.' \"\$file\" 2>/dev/null || command cat \"\$file\"
                        ;;
                    *)
                        command cat \"\$file\"
                        ;;
                esac
                ;;
        esac
    done
}
EOF"
        echo -e " ${GREEN}✓ Done${NC}"
    fi
fi

echo ""
echo -e "${CYAN}${BOLD}============================================${NC}"
echo -e "${GREEN}${BOLD}   Installation Complete!${NC}"
echo -e "${CYAN}${BOLD}============================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  ${BLUE}1.${NC} Log out and log back in for changes to take effect"
echo -e "  ${BLUE}2.${NC} Run ${CYAN}'zsh'${NC} to start using your new shell"
echo -e "  ${BLUE}3.${NC} Open Neovim to trigger plugin installation"
echo ""
echo -e "${MAGENTA}Installation log:${NC} $LOG_FILE"
echo ""
