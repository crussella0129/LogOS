#!/bin/bash

################################################################################
# LogOS Post-Installation - Tier 2 (Desktop & Workstation)
# Run this script after first boot into LogOS
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; }
warning() { echo -e "${YELLOW}⚠${NC} $*"; }
info() { echo -e "${BLUE}?${NC} $*"; }

# Check if running as normal user (not root)
if [[ $EUID -eq 0 ]]; then
    error "Do not run this script as root. Run as your normal user."
    exit 1
fi

clear
cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║         LogOS Tier 2: Desktop & Workstation Setup           ║
╚══════════════════════════════════════════════════════════════╝

This script will install:
- AUR helper (yay)
- Graphics drivers
- Desktop environment
- Essential desktop applications
- Development tools
- Terminal enhancements
- Fonts

EOF

read -p "Press ENTER to continue..."

################################################################################
# Detect System Configuration
################################################################################

log "Detecting system configuration..."

# Detect GPU
if lspci | grep -i nvidia &>/dev/null; then
    GPU_TYPE="nvidia"
    warning "NVIDIA GPU detected"
elif lspci | grep -i amd | grep -i vga &>/dev/null; then
    GPU_TYPE="amd"
    success "AMD GPU detected"
elif lspci | grep -i intel | grep -i vga &>/dev/null; then
    GPU_TYPE="intel"
    success "Intel GPU detected"
else
    GPU_TYPE="none"
    info "No discrete GPU detected"
fi

# Ask for desktop environment
echo ""
echo "Select Desktop Environment:"
echo "1) GNOME (Recommended for workstations)"
echo "2) KDE Plasma (Power users/Gaming)"
echo "3) XFCE (Lightweight)"
echo "4) i3-wm (Tiling)"
echo "5) Skip desktop installation"
read -p "Enter choice [1]: " DE_CHOICE

case "${DE_CHOICE:-1}" in
    1) DESKTOP_ENV="gnome" ;;
    2) DESKTOP_ENV="kde" ;;
    3) DESKTOP_ENV="xfce" ;;
    4) DESKTOP_ENV="i3" ;;
    5) DESKTOP_ENV="none" ;;
    *) DESKTOP_ENV="gnome" ;;
esac

################################################################################
# System Update
################################################################################

log "Updating system..."
sudo pacman -Syu --noconfirm

################################################################################
# Install AUR Helper (yay)
################################################################################

log "Installing AUR helper (yay)..."
sudo pacman -S --needed --noconfirm base-devel git

if ! command -v yay &>/dev/null; then
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ..
    rm -rf yay
    success "yay installed"
else
    success "yay already installed"
fi

################################################################################
# Graphics Drivers
################################################################################

log "Installing graphics drivers for: $GPU_TYPE..."

case "$GPU_TYPE" in
    amd)
        sudo pacman -S --noconfirm \
            mesa vulkan-radeon libva-mesa-driver \
            xf86-video-amdgpu mesa-vdpau
        ;;
    nvidia)
        warning "Installing NVIDIA drivers..."
        sudo pacman -S --noconfirm \
            nvidia-dkms nvidia-utils nvidia-settings \
            lib32-nvidia-utils cuda cudnn
        sudo nvidia-xconfig
        ;;
    intel)
        sudo pacman -S --noconfirm \
            mesa vulkan-intel intel-media-driver \
            xf86-video-intel
        ;;
    none)
        sudo pacman -S --noconfirm mesa
        ;;
esac

success "Graphics drivers installed"

################################################################################
# Desktop Environment
################################################################################

if [[ "$DESKTOP_ENV" != "none" ]]; then
    log "Installing desktop environment: $DESKTOP_ENV..."

    case "$DESKTOP_ENV" in
        gnome)
            sudo pacman -S --noconfirm \
                gnome gnome-extra gnome-tweaks \
                gnome-shell-extensions gdm \
                gnome-browser-connector dconf-editor
            sudo systemctl enable gdm
            ;;
        kde)
            sudo pacman -S --noconfirm \
                plasma plasma-meta plasma-wayland-session \
                kde-applications-meta sddm \
                packagekit-qt6 plasma-systemmonitor \
                kde-gtk-config breeze-gtk
            sudo systemctl enable sddm
            ;;
        xfce)
            sudo pacman -S --noconfirm \
                xfce4 xfce4-goodies \
                lightdm lightdm-gtk-greeter \
                network-manager-applet \
                thunar-archive-plugin thunar-media-tags-plugin
            sudo systemctl enable lightdm
            ;;
        i3)
            sudo pacman -S --noconfirm \
                i3-wm i3status i3lock dmenu \
                lightdm lightdm-gtk-greeter \
                nitrogen picom alacritty rofi dunst \
                polybar xorg-server xorg-xinit
            sudo systemctl enable lightdm
            ;;
    esac

    success "Desktop environment installed"
fi

################################################################################
# Essential Desktop Applications
################################################################################

log "Installing essential desktop applications..."

sudo pacman -S --noconfirm \
    firefox chromium \
    thunderbird \
    libreoffice-fresh \
    gimp inkscape \
    vlc mpv \
    evince \
    gnome-calculator \
    gnome-disk-utility \
    gparted \
    file-roller \
    keepassxc \
    flameshot

success "Desktop applications installed"

################################################################################
# Development Tools
################################################################################

log "Installing development tools..."

sudo pacman -S --noconfirm \
    git git-lfs \
    python python-pip python-virtualenv \
    nodejs npm \
    rust cargo \
    go \
    jdk-openjdk \
    cmake ninja meson \
    gdb valgrind \
    docker docker-compose \
    code

# Enable Docker
sudo systemctl enable docker
sudo usermod -aG docker $USER

success "Development tools installed"

################################################################################
# Terminal Enhancements
################################################################################

log "Installing terminal enhancements..."

sudo pacman -S --noconfirm \
    zsh zsh-completions \
    tmux \
    htop btop \
    neofetch \
    fzf ripgrep fd bat eza \
    tree ncdu \
    wget curl httpie \
    jq yq

success "Terminal tools installed"

################################################################################
# Fonts
################################################################################

log "Installing fonts..."

sudo pacman -S --noconfirm \
    ttf-dejavu ttf-liberation \
    noto-fonts noto-fonts-emoji noto-fonts-cjk \
    ttf-fira-code ttf-jetbrains-mono \
    adobe-source-code-pro-fonts \
    terminus-font

success "Fonts installed"

################################################################################
# LogOS Branding & Wallpaper
################################################################################

log "Installing LogOS branding and wallpaper..."

# Create wallpaper directory
sudo mkdir -p /usr/share/backgrounds/logos

# Get script directory (assuming this is run from installer/modules)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Copy wallpaper to system location
if [[ -f "${SCRIPT_DIR}/assets/branding/logos-wallpaper.png" ]]; then
    sudo cp "${SCRIPT_DIR}/assets/branding/logos-wallpaper.png" /usr/share/backgrounds/logos/
    success "LogOS wallpaper installed"
else
    warning "Wallpaper not found in installer assets, skipping..."
fi

# Also copy to user's Pictures directory
mkdir -p ~/Pictures/Wallpapers
if [[ -f "${SCRIPT_DIR}/assets/branding/logos-wallpaper.png" ]]; then
    cp "${SCRIPT_DIR}/assets/branding/logos-wallpaper.png" ~/Pictures/Wallpapers/
fi

# Set wallpaper based on desktop environment
if [[ "$DESKTOP_ENV" != "none" ]]; then
    log "Setting LogOS wallpaper for $DESKTOP_ENV..."

    case "$DESKTOP_ENV" in
        gnome)
            # GNOME wallpaper setting
            if [[ -f /usr/share/backgrounds/logos/logos-wallpaper.png ]]; then
                # Set for current user
                gsettings set org.gnome.desktop.background picture-uri "file:///usr/share/backgrounds/logos/logos-wallpaper.png" 2>/dev/null || true
                gsettings set org.gnome.desktop.background picture-uri-dark "file:///usr/share/backgrounds/logos/logos-wallpaper.png" 2>/dev/null || true
                gsettings set org.gnome.desktop.background picture-options "zoom" 2>/dev/null || true
                success "GNOME wallpaper configured"
            fi
            ;;
        kde)
            # KDE Plasma wallpaper setting
            if [[ -f /usr/share/backgrounds/logos/logos-wallpaper.png ]]; then
                # Create KDE wallpaper script
                cat > /tmp/set-kde-wallpaper.js <<'KDESCRIPT'
var allDesktops = desktops();
for (i=0;i<allDesktops.length;i++) {
    d = allDesktops[i];
    d.wallpaperPlugin = "org.kde.image";
    d.currentConfigGroup = Array("Wallpaper", "org.kde.image", "General");
    d.writeConfig("Image", "file:///usr/share/backgrounds/logos/logos-wallpaper.png");
}
KDESCRIPT
                # Note: This will be applied on next login
                success "KDE wallpaper script created (will apply on next login)"
            fi
            ;;
        xfce)
            # XFCE wallpaper setting
            if [[ -f /usr/share/backgrounds/logos/logos-wallpaper.png ]]; then
                xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image \
                    -s /usr/share/backgrounds/logos/logos-wallpaper.png 2>/dev/null || true
                success "XFCE wallpaper configured"
            fi
            ;;
        i3)
            # i3-wm wallpaper using feh
            if [[ -f /usr/share/backgrounds/logos/logos-wallpaper.png ]]; then
                # Add to i3 config
                mkdir -p ~/.config/i3
                if ! grep -q "logos-wallpaper" ~/.config/i3/config 2>/dev/null; then
                    echo "exec --no-startup-id feh --bg-scale /usr/share/backgrounds/logos/logos-wallpaper.png" >> ~/.config/i3/config
                fi
                # Install feh if not present
                sudo pacman -S --noconfirm --needed feh
                success "i3-wm wallpaper configured"
            fi
            ;;
    esac
fi

success "LogOS branding installed"

################################################################################
# Snapshot System
################################################################################

log "Installing snapshot system..."

sudo pacman -S --noconfirm snapper grub-btrfs snap-pac

# Create root config
sudo snapper -c root create-config /

# Adjust timeline settings
sudo sed -i 's/TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="5"/' /etc/snapper/configs/root
sudo sed -i 's/TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/' /etc/snapper/configs/root
sudo sed -i 's/TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="4"/' /etc/snapper/configs/root
sudo sed -i 's/TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="6"/' /etc/snapper/configs/root

# Enable snapper timers
sudo systemctl enable --now snapper-timeline.timer
sudo systemctl enable --now snapper-cleanup.timer
sudo systemctl enable --now grub-btrfsd

# Create initial snapshot
sudo snapper -c root create --description "Post-Tier2 installation"

success "Snapshot system configured"

################################################################################
# Completion
################################################################################

clear
cat << 'EOF'

╔══════════════════════════════════════════════════════════════╗
║            Tier 2 Installation Complete!                     ║
╚══════════════════════════════════════════════════════════════╝

Installed:
✓ Graphics drivers
✓ Desktop environment
✓ Desktop applications
✓ Development tools
✓ Terminal enhancements
✓ Fonts
✓ Snapshot system (Snapper)

Next Steps:
1. Reboot to start the desktop environment: sudo reboot
2. After reboot, optionally run Tier 3 for specialized tools:
   - ./installer/modules/tier3-standalone.sh

3. Configure your desktop environment and applications

EOF

log "Tier 2 installation completed successfully"
