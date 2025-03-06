#!/bin/bash

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)." >&2
    exit 1
fi

PACKAGES=("git" "curl" "tmux" "btop" "build-essential" "ripgrep" "eza" "zsh" "unzip" "python3.13" "stow")
PPAS=("ppa:deadsnakes/ppa")

if command -v apt &>/dev/null; then
    PKG_MANAGER="apt"
    UPDATE_CMD="apt update"
    INSTALL_CMD="apt install -y"
else
    echo "Unsupported package manager. Exiting."
    exit 1
fi


echo "Updating package list..."
sudo $UPDATE_CMD

# Add PPAs
for ppa in "${PPAS[@]}"; do
    if ! grep -q "^deb .*$ppa" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
        echo "Adding $ppa..."
        sudo add-apt-repository -y "$ppa"
    else
        echo "$ppa is already added. Skipping."
    fi
done

for package in "${PACKAGES[@]}"; do
    if ! command -v "$package" &>/dev/null; then
        echo "Installing $package..."
        sudo $INSTALL_CMD "$package"
    else
        echo "$package is already installed. Skipping."
    fi
done

# Change shell to zsh
sudo chsh -s $(which zsh)

# Install oh-my-zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Get my zsh config from git
FOURSIGHT_URL = "https://raw.githubusercontent.com/f0ur3y3s/dotfiles/refs/heads/main/omzsh/foursight.zsh-theme"
TARGET_DIR = "$HOME/.oh-my-zsh/custom/themes"
FOURSIGHT_FILENAME = $(basename $FOURSIGHT_URL)

mkdir -p $TARGET_DIR
curl -o "$TARGET_DIR/$FOURSIGHT_FILENAME" "$FOURSIGHT_URL"

# Change zsh theme
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="foursight"/' ~/.zshrc

source ~/.zshrc

# Get my neovim config from git
# sh -c "$(curl -fsSL git@github.com:f0ur3y3s/nvim.git)"
NVIM_URL = ""
TARGET_DIR = "$HOME/.config/nvim"

mkdir -p $TARGET_DIR

curl -o "$TARGET_DIR" "$NVIM_URL"
