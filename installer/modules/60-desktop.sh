#!/bin/bash

################################################################################
# LogOS Installer - Desktop Environment Installation Module
# Installs the selected desktop environment and enables the display manager
################################################################################

install_desktop() {
    # Skip if no desktop environment selected
    if [[ "${DESKTOP_ENV:-none}" == "none" ]]; then
        log "Skipping desktop installation (server mode)"
        return 0
    fi

    log "Installing desktop environment: $DESKTOP_ENV..."

    # Install Xorg base first (required for all desktop environments)
    log "Installing Xorg base..."
    pacstrap /mnt xorg-server xorg-xinit xorg-xrandr xorg-xsetroot

    # Install GPU drivers
    install_gpu_drivers

    # Install desktop environment packages
    case "$DESKTOP_ENV" in
        gnome)
            install_gnome
            ;;
        kde)
            install_kde
            ;;
        xfce)
            install_xfce
            ;;
        i3)
            install_i3
            ;;
        *)
            warning "Unknown desktop environment: $DESKTOP_ENV"
            return 1
            ;;
    esac

    # Set graphical target as default
    log "Setting graphical.target as default..."
    arch_chroot "systemctl set-default graphical.target"

    success "Desktop environment installed and configured"
}

install_gpu_drivers() {
    log "Installing GPU drivers for: ${GPU_TYPE:-auto}..."

    case "${GPU_TYPE:-auto}" in
        amd)
            pacstrap /mnt mesa vulkan-radeon libva-mesa-driver \
                xf86-video-amdgpu mesa-vdpau lib32-mesa lib32-vulkan-radeon
            ;;
        nvidia)
            pacstrap /mnt nvidia-dkms nvidia-utils nvidia-settings \
                lib32-nvidia-utils
            ;;
        intel)
            pacstrap /mnt mesa vulkan-intel intel-media-driver \
                xf86-video-intel lib32-mesa lib32-vulkan-intel
            ;;
        auto|*)
            # Install basic mesa drivers for all GPUs
            pacstrap /mnt mesa lib32-mesa
            # Detect and install specific drivers
            if lspci | grep -i nvidia &>/dev/null; then
                warning "NVIDIA GPU detected, installing drivers..."
                pacstrap /mnt nvidia-dkms nvidia-utils nvidia-settings || true
            fi
            if lspci | grep -i "amd\|radeon" | grep -i vga &>/dev/null; then
                pacstrap /mnt vulkan-radeon xf86-video-amdgpu || true
            fi
            if lspci | grep -i intel | grep -i vga &>/dev/null; then
                pacstrap /mnt vulkan-intel intel-media-driver || true
            fi
            ;;
    esac

    success "GPU drivers installed"
}

install_gnome() {
    log "Installing GNOME desktop environment..."

    # Install GNOME packages
    pacstrap /mnt \
        gnome \
        gnome-tweaks \
        gdm \
        gnome-browser-connector \
        networkmanager \
        pipewire pipewire-pulse pipewire-alsa wireplumber

    # Enable GDM
    log "Enabling GDM display manager..."
    arch_chroot "systemctl enable gdm"
    arch_chroot "systemctl enable NetworkManager"

    success "GNOME installed with GDM"
}

install_kde() {
    log "Installing KDE Plasma desktop environment..."

    # Install KDE Plasma packages
    pacstrap /mnt \
        plasma-meta \
        plasma-wayland-session \
        kde-applications-meta \
        sddm \
        packagekit-qt6 \
        networkmanager \
        pipewire pipewire-pulse pipewire-alsa wireplumber

    # Enable SDDM
    log "Enabling SDDM display manager..."
    arch_chroot "systemctl enable sddm"
    arch_chroot "systemctl enable NetworkManager"

    success "KDE Plasma installed with SDDM"
}

install_xfce() {
    log "Installing XFCE desktop environment..."

    # Install XFCE packages
    pacstrap /mnt \
        xfce4 \
        xfce4-goodies \
        lightdm \
        lightdm-gtk-greeter \
        lightdm-gtk-greeter-settings \
        network-manager-applet \
        networkmanager \
        pipewire pipewire-pulse pipewire-alsa wireplumber

    # Enable LightDM
    log "Enabling LightDM display manager..."
    arch_chroot "systemctl enable lightdm"
    arch_chroot "systemctl enable NetworkManager"

    success "XFCE installed with LightDM"
}

install_i3() {
    log "Installing i3 window manager..."

    # Install i3 packages
    pacstrap /mnt \
        i3-wm \
        i3status \
        i3lock \
        dmenu \
        lightdm \
        lightdm-gtk-greeter \
        alacritty \
        rofi \
        dunst \
        nitrogen \
        picom \
        networkmanager \
        network-manager-applet \
        pipewire pipewire-pulse pipewire-alsa wireplumber

    # Enable LightDM
    log "Enabling LightDM display manager..."
    arch_chroot "systemctl enable lightdm"
    arch_chroot "systemctl enable NetworkManager"

    success "i3 installed with LightDM"
}
