#!/bin/bash

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)." >&2
    exit 1
fi

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
    "docker.io" "docker-compose" "containerd"
    # Network tools
    "socat" "ncat" "net-tools" "sshpass" "bind9-dnsutils"
    # Terminal utilities
    "cowsay" "fortune-mod"
)
# Note: neovim, btop, eza, glow, and zsh-autosuggestions need special handling

if command -v apt &>/dev/null; then
    PKG_MANAGER="apt"
    UPDATE_CMD="apt update"
    INSTALL_CMD="apt install -y"
else
    echo "Unsupported package manager. Exiting."
    exit 1
fi

# Fix CD-ROM repository issue first
echo "Fixing repository configuration..."
if grep -q "cdrom:" /etc/apt/sources.list; then
    echo "Commenting out CD-ROM repositories..."
    sed -i 's/^deb cdrom:/#deb cdrom:/' /etc/apt/sources.list
fi

echo "Updating package list..."
$UPDATE_CMD

# Handle Debian-specific package installations
echo "Setting up additional repositories for Debian..."

# Add backports for newer packages
if ! grep -q "bookworm-backports" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
    echo "Adding Debian backports repository..."
    echo "deb http://deb.debian.org/debian bookworm-backports main" >> /etc/apt/sources.list.d/backports.list
    $UPDATE_CMD
fi

# For Python 3.13 on Debian, we'll compile from source or use alternative methods
# For now, we'll use the available Python version
PYTHON_PKG=$(apt list --available python3.* 2>/dev/null | grep -E "python3\.[0-9]+/" | sort -V | tail -1 | cut -d'/' -f1 | cut -d' ' -f1)
if [[ -n "$PYTHON_PKG" ]]; then
    PACKAGES+=("$PYTHON_PKG" "${PYTHON_PKG}-pip" "${PYTHON_PKG}-venv")
fi

# Install packages
for package in "${PACKAGES[@]}"; do
    if ! dpkg -l | grep -q "^ii  $package "; then
        echo "Installing $package..."
        $INSTALL_CMD "$package"
    else
        echo "$package is already installed. Skipping."
    fi
done

# Install latest Neovim from GitHub
if ! command -v nvim &>/dev/null || [[ $(nvim --version | head -1 | grep -o '0\.[0-9]\+' | head -1) < "0.11" ]]; then
    echo "Installing latest Neovim from GitHub..."
    NVIM_VERSION=$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    NVIM_URL="https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-linux64.tar.gz"

    cd /tmp
    curl -LO "$NVIM_URL"
    tar xzf nvim-linux64.tar.gz

    # Remove old neovim if it exists
    rm -rf /usr/local/nvim-linux64

    # Install to /usr/local
    mv nvim-linux64 /usr/local/
    ln -sf /usr/local/nvim-linux64/bin/nvim /usr/local/bin/nvim

    # Cleanup
    rm -f nvim-linux64.tar.gz
    cd /

    echo "Installed Neovim v${NVIM_VERSION}"
else
    echo "Neovim is already installed and up to date. Skipping."
fi

# Get the actual user (not root) for user-specific operations
ACTUAL_USER=${SUDO_USER:-$USER}
ACTUAL_HOME=$(eval echo ~$ACTUAL_USER)

echo "Setting up for user: $ACTUAL_USER"
echo "Home directory: $ACTUAL_HOME"

# Change shell to zsh for the actual user
if [[ $(getent passwd "$ACTUAL_USER" | cut -d: -f7) != "$(which zsh)" ]]; then
    echo "Changing shell to zsh for $ACTUAL_USER..."
    chsh -s "$(which zsh)" "$ACTUAL_USER"
else
    echo "Shell is already zsh for $ACTUAL_USER. Skipping."
fi

# Install oh-my-zsh as the actual user
if [[ ! -d "$ACTUAL_HOME/.oh-my-zsh" ]]; then
    echo "Installing oh-my-zsh..."
    sudo -u "$ACTUAL_USER" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
    echo "oh-my-zsh is already installed. Skipping."
fi

# Get custom zsh theme
FOURSIGHT_URL="https://raw.githubusercontent.com/f0ur3y3s/dotfiles/refs/heads/main/omzsh/foursight.zsh-theme"
TARGET_DIR="$ACTUAL_HOME/.oh-my-zsh/custom/themes"
FOURSIGHT_FILENAME=$(basename "$FOURSIGHT_URL")

echo "Setting up custom zsh theme..."
sudo -u "$ACTUAL_USER" mkdir -p "$TARGET_DIR"
sudo -u "$ACTUAL_USER" curl -o "$TARGET_DIR/$FOURSIGHT_FILENAME" "$FOURSIGHT_URL"

# Update .zshrc to use the custom theme
if [[ -f "$ACTUAL_HOME/.zshrc" ]]; then
    sudo -u "$ACTUAL_USER" sed -i 's/ZSH_THEME=".*"/ZSH_THEME="foursight"/' "$ACTUAL_HOME/.zshrc"
    echo "Updated zsh theme to foursight."
else
    echo "Warning: .zshrc not found. You may need to run zsh setup manually."
fi

# Install zsh-autosuggestions
ZSH_AUTOSUGGESTIONS_DIR="$ACTUAL_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
if [[ ! -d "$ZSH_AUTOSUGGESTIONS_DIR" ]]; then
    echo "Installing zsh-autosuggestions..."
    sudo -u "$ACTUAL_USER" git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_AUTOSUGGESTIONS_DIR"

    # Add to plugins in .zshrc if not already present
    if [[ -f "$ACTUAL_HOME/.zshrc" ]] && ! grep -q "zsh-autosuggestions" "$ACTUAL_HOME/.zshrc"; then
        # Replace plugins line to include zsh-autosuggestions
        sudo -u "$ACTUAL_USER" sed -i 's/^plugins=(\(.*\))/plugins=(\1 zsh-autosuggestions)/' "$ACTUAL_HOME/.zshrc"
        echo "Added zsh-autosuggestions to .zshrc plugins."
    fi
else
    echo "zsh-autosuggestions is already installed. Skipping."
fi

# Setup Neovim config
NVIM_CONFIG_DIR="$ACTUAL_HOME/.config/nvim"
NVIM_REPO="https://github.com/f0ur3y3s/nvim.git"

if [[ ! -d "$NVIM_CONFIG_DIR" ]]; then
    echo "Setting up Neovim configuration..."
    sudo -u "$ACTUAL_USER" mkdir -p "$ACTUAL_HOME/.config"
    sudo -u "$ACTUAL_USER" git clone "$NVIM_REPO" "$NVIM_CONFIG_DIR"
else
    echo "Neovim config directory already exists. Skipping."
fi

# Install Node.js (often needed for Neovim plugins)
if ! command -v node &>/dev/null; then
    echo "Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    $INSTALL_CMD nodejs
else
    echo "Node.js is already installed. Skipping."
fi

# Install Rust (useful for various tools)
if ! command -v rustc &>/dev/null; then
    echo "Installing Rust..."
    sudo -u "$ACTUAL_USER" curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sudo -u "$ACTUAL_USER" sh -s -- -y
    # Add cargo to PATH for current session
    export PATH="$ACTUAL_HOME/.cargo/bin:$PATH"
else
    echo "Rust is already installed. Skipping."
fi

# Setup Docker group for user
if command -v docker &>/dev/null; then
    echo "Configuring Docker for user $ACTUAL_USER..."
    if ! groups "$ACTUAL_USER" | grep -q docker; then
        usermod -aG docker "$ACTUAL_USER"
        echo "Added $ACTUAL_USER to docker group. You'll need to log out and back in for this to take effect."
    else
        echo "User $ACTUAL_USER is already in docker group."
    fi
fi

# Install packages that aren't available in standard repos via alternative methods
echo "Installing additional tools..."

# Install btop (system monitor)
if ! command -v btop &>/dev/null; then
    echo "Installing btop..."
    # Try from backports first, fallback to manual installation
    if ! $INSTALL_CMD -t bookworm-backports btop 2>/dev/null; then
        echo "Installing btop from GitHub releases..."
        BTOP_URL=$(curl -s https://api.github.com/repos/aristocratos/btop/releases/latest | grep -o 'https://.*btop.*linux.*x86_64.*tbz' | head -1)
        if [[ -n "$BTOP_URL" ]]; then
            cd /tmp
            curl -L "$BTOP_URL" -o btop.tbz
            tar -xf btop.tbz
            cd btop
            make install PREFIX=/usr/local
            cd /
            rm -rf /tmp/btop*
        fi
    fi
else
    echo "btop is already installed. Skipping."
fi

# Install eza (modern ls replacement)
if ! command -v eza &>/dev/null; then
    echo "Installing eza..."
    # eza is not in Debian repos, install from GitHub
    EZA_URL=$(curl -s https://api.github.com/repos/eza-community/eza/releases/latest | grep -o 'https://.*eza.*linux.*x86_64.*tar\.gz' | head -1)
    if [[ -n "$EZA_URL" ]]; then
        cd /tmp
        curl -L "$EZA_URL" -o eza.tar.gz
        tar -xzf eza.tar.gz
        cp eza /usr/local/bin/
        chmod +x /usr/local/bin/eza
        rm -f eza.tar.gz eza
        cd /
    fi
else
    echo "eza is already installed. Skipping."
fi

# Install glow (markdown viewer)
if ! command -v glow &>/dev/null; then
    echo "Installing glow..."
    GLOW_URL=$(curl -s https://api.github.com/repos/charmbracelet/glow/releases/latest | grep -o 'https://.*glow.*linux.*x86_64.*tar\.gz' | grep -v 'sbom' | head -1)
    if [[ -n "$GLOW_URL" ]]; then
        cd /tmp
        curl -L "$GLOW_URL" -o glow.tar.gz
        tar -xzf glow.tar.gz
        cp glow /usr/local/bin/
        chmod +x /usr/local/bin/glow
        rm -f glow.tar.gz glow LICENSE README.md completions
        cd /
    fi
else
    echo "glow is already installed. Skipping."
fi

# Setup clang alternatives to use clang-18 as default
if command -v clang-18 &>/dev/null; then
    echo "Setting up clang-18 as default clang..."
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-18 100 \
        --slave /usr/bin/clang++ clang++ /usr/bin/clang++-18 \
        --slave /usr/bin/clangd clangd /usr/bin/clangd-18 \
        --slave /usr/bin/clang-format clang-format /usr/bin/clang-format-18 \
        --slave /usr/bin/clang-tidy clang-tidy /usr/bin/clang-tidy-18 \
        --slave /usr/bin/lldb lldb /usr/bin/lldb-18 \
        --slave /usr/bin/lld lld /usr/bin/lld-18 || true
fi

# Create some useful aliases in .zshrc if they don't exist
ZSHRC_FILE="$ACTUAL_HOME/.zshrc"
if [[ -f "$ZSHRC_FILE" ]]; then
    echo "Adding useful aliases to .zshrc..."

    # Add aliases section if it doesn't exist
    if ! grep -q "# Custom aliases" "$ZSHRC_FILE"; then
        sudo -u "$ACTUAL_USER" bash -c "cat >> '$ZSHRC_FILE' << 'EOF'

# Custom aliases
alias ll='eza -la --git --icons'
alias la='eza -a --git --icons'
alias ls='eza --git --icons'
alias lt='eza -la --tree --level=2 --git --icons'
alias clang='clang-18'
alias clang++='clang++-18'
EOF"
        echo "Added custom aliases to .zshrc."
    fi
fi

echo "Setup complete!"
echo "Please log out and log back in (or restart) for shell changes to take effect."
echo "Then run 'zsh' to start using your new shell setup."
