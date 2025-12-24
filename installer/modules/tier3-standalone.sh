#!/bin/bash

################################################################################
# LogOS Post-Installation - Tier 3 (Specialized Capabilities)
# Run this script after Tier 2, based on your needs
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
info() { echo -e "${BLUE}ℹ${NC} $*"; }
warning() { echo -e "${YELLOW}?${NC} $*"; }

# Check if running as normal user
if [[ $EUID -eq 0 ]]; then
    error "Do not run this script as root. Run as your normal user."
    exit 1
fi

clear
cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║      LogOS Tier 3: Specialized Capabilities Setup           ║
╚══════════════════════════════════════════════════════════════╝

Select the categories you want to install:
EOF

# Category selection
declare -A CATEGORIES

echo ""
read -p "Install CAD & 3D Modeling? (y/N): " response
[[ "$response" =~ ^[Yy]$ ]] && CATEGORIES[cad]=1

read -p "Install 3D Printing tools? (y/N): " response
[[ "$response" =~ ^[Yy]$ ]] && CATEGORIES[printing]=1

read -p "Install Gaming tools? (y/N): " response
[[ "$response" =~ ^[Yy]$ ]] && CATEGORIES[gaming]=1

read -p "Install Security Research tools? (y/N): " response
[[ "$response" =~ ^[Yy]$ ]] && CATEGORIES[security]=1

read -p "Install Virtualization & Containers? (y/N): " response
[[ "$response" =~ ^[Yy]$ ]] && CATEGORIES[virt]=1

read -p "Install Knowledge Preservation tools? (y/N): " response
[[ "$response" =~ ^[Yy]$ ]] && CATEGORIES[knowledge]=1

read -p "Install Scientific Computing tools? (y/N): " response
[[ "$response" =~ ^[Yy]$ ]] && CATEGORIES[science]=1

read -p "Install Media Production tools? (y/N): " response
[[ "$response" =~ ^[Yy]$ ]] && CATEGORIES[media]=1

read -p "Install Power Management tools? (y/N): " response
[[ "$response" =~ ^[Yy]$ ]] && CATEGORIES[power]=1

echo ""
log "Starting Tier 3 installation..."

################################################################################
# CAD & 3D Modeling
################################################################################

if [[ ${CATEGORIES[cad]:-0} -eq 1 ]]; then
    log "Installing CAD & 3D Modeling tools..."

    sudo pacman -S --noconfirm \
        freecad openscad blender librecad

    yay -S --noconfirm kicad || warning "KiCad installation failed"

    mkdir -p ~/Engineering/{CAD,PCB,3DModels}

    success "CAD & 3D Modeling tools installed"
fi

################################################################################
# 3D Printing
################################################################################

if [[ ${CATEGORIES[printing]:-0} -eq 1 ]]; then
    log "Installing 3D Printing tools..."

    sudo pacman -S --noconfirm prusa-slicer openscad

    yay -S --noconfirm \
        orca-slicer-bin \
        cura-bin || warning "Some slicer installations failed"

    mkdir -p ~/Engineering/3DPrinting/{STL,GCODE,Projects}

    success "3D Printing tools installed"
fi

################################################################################
# Gaming
################################################################################

if [[ ${CATEGORIES[gaming]:-0} -eq 1 ]]; then
    log "Installing Gaming tools..."

    sudo pacman -S --noconfirm \
        steam lutris \
        wine-staging winetricks \
        gamemode lib32-gamemode \
        mangohud lib32-mangohud \
        vkd3d lib32-vkd3d

    # Proton/Wine dependencies
    sudo pacman -S --noconfirm \
        lib32-mesa lib32-vulkan-radeon \
        lib32-alsa-plugins lib32-libpulse \
        lib32-openal

    # Disable CoW for game directories
    mkdir -p ~/.local/share/Steam/steamapps ~/Games
    chattr +C ~/.local/share/Steam/steamapps 2>/dev/null || true
    chattr +C ~/Games 2>/dev/null || true

    success "Gaming tools installed"
fi

################################################################################
# Security Research
################################################################################

if [[ ${CATEGORIES[security]:-0} -eq 1 ]]; then
    log "Installing Security Research tools..."

    sudo pacman -S --noconfirm \
        nmap wireshark-qt tcpdump \
        aircrack-ng hashcat john \
        sqlmap nikto gobuster hydra \
        radare2 ghex

    yay -S --noconfirm \
        metasploit \
        burpsuite || warning "Some security tools failed to install"

    # Add user to wireshark group
    sudo usermod -aG wireshark $USER

    success "Security Research tools installed"
fi

################################################################################
# Virtualization & Containers
################################################################################

if [[ ${CATEGORIES[virt]:-0} -eq 1 ]]; then
    log "Installing Virtualization & Containers..."

    sudo pacman -S --noconfirm \
        qemu-full virt-manager libvirt \
        docker docker-compose \
        podman buildah skopeo \
        kubectl helm k9s

    yay -S --noconfirm minikube-bin || warning "Minikube installation failed"

    # Enable services
    sudo systemctl enable --now docker libvirtd
    sudo usermod -aG docker,libvirt $USER

    success "Virtualization & Containers installed"
fi

################################################################################
# Knowledge Preservation
################################################################################

if [[ ${CATEGORIES[knowledge]:-0} -eq 1 ]]; then
    log "Installing Knowledge Preservation tools..."

    sudo pacman -S --noconfirm calibre

    yay -S --noconfirm \
        kiwix-desktop-bin \
        zotero-bin \
        obsidian || warning "Some knowledge tools failed to install"

    # Create knowledge directories
    mkdir -p ~/Documents/{Books,Papers,Kiwix,Archive}
    mkdir -p ~/Documents/Kiwix/Library

    success "Knowledge Preservation tools installed"
fi

################################################################################
# Scientific Computing
################################################################################

if [[ ${CATEGORIES[science]:-0} -eq 1 ]]; then
    log "Installing Scientific Computing tools..."

    sudo pacman -S --noconfirm \
        python-numpy python-scipy python-pandas \
        python-matplotlib python-scikit-learn \
        jupyter-notebook jupyterlab \
        r octave gnuplot \
        maxima wxmaxima

    # Create research environment
    mkdir -p ~/Research/{Notebooks,Data,Output}

    success "Scientific Computing tools installed"
fi

################################################################################
# Media Production
################################################################################

if [[ ${CATEGORIES[media]:-0} -eq 1 ]]; then
    log "Installing Media Production tools..."

    sudo pacman -S --noconfirm \
        audacity ardour obs-studio \
        kdenlive handbrake \
        ffmpeg imagemagick

    yay -S --noconfirm \
        reaper-bin \
        davinci-resolve || warning "Some media tools failed to install"

    success "Media Production tools installed"
fi

################################################################################
# Power Management
################################################################################

if [[ ${CATEGORIES[power]:-0} -eq 1 ]]; then
    log "Installing Power Management tools..."

    sudo pacman -S --noconfirm \
        tlp tlp-rdw powertop \
        acpi acpid thermald

    # Enable services
    sudo systemctl enable tlp acpid
    sudo systemctl mask systemd-rfkill.service systemd-rfkill.socket

    # Create TLP configuration
    sudo tee /etc/tlp.d/01-logos.conf > /dev/null <<'EOF'
# LogOS Power Configuration
CPU_SCALING_GOVERNOR_ON_AC=performance
CPU_SCALING_GOVERNOR_ON_BAT=powersave
CPU_BOOST_ON_AC=1
CPU_BOOST_ON_BAT=0
PLATFORM_PROFILE_ON_AC=performance
PLATFORM_PROFILE_ON_BAT=low-power
WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=on
USB_AUTOSUSPEND=1
RUNTIME_PM_ON_AC=auto
RUNTIME_PM_ON_BAT=auto
EOF

    # Start TLP
    sudo tlp start

    # Create power profile script
    sudo tee /usr/local/bin/logos-power > /dev/null <<'EOF'
#!/bin/bash
case "$1" in
    gael)
        sudo tlp bat
        sudo cpupower frequency-set -g powersave 2>/dev/null
        echo "Power: Gael (Conservative)"
        ;;
    midir)
        sudo tlp start
        echo "Power: Midir (Balanced)"
        ;;
    halflight)
        sudo tlp ac
        sudo cpupower frequency-set -g performance 2>/dev/null
        echo "Power: Halflight (Performance)"
        ;;
    status)
        tlp-stat -s
        ;;
    *)
        echo "Usage: logos-power {gael|midir|halflight|status}"
        ;;
esac
EOF

    sudo chmod +x /usr/local/bin/logos-power

    success "Power Management tools installed"
fi

################################################################################
# Create final snapshot
################################################################################

log "Creating post-installation snapshot..."
sudo snapper -c root create --description "Post-Tier3 installation"

################################################################################
# Completion
################################################################################

clear
cat << 'EOF'

╔══════════════════════════════════════════════════════════════╗
║         Tier 3 Installation Complete!                        ║
╚══════════════════════════════════════════════════════════════╝

Your LogOS installation is now complete with specialized tools.

Useful Commands:
- logos-power {gael|midir|halflight|status} - Manage power profiles
- sudo snapper list - View system snapshots
- sudo grub-mkconfig -o /boot/grub/grub.cfg - Update GRUB menu with snapshots

Next Steps:
1. Reboot if you installed new services or drivers
2. Explore the Ringed City boot profiles (Gael, Midir, Halflight)
3. Configure your specialized applications
4. Review LogOS_Build_Guide_2025_MASTER_v7.md for advanced features

Thank you for installing LogOS!

EOF

log "Tier 3 installation completed successfully"
