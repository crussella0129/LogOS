#!/usr/bin/env bash
# LogOS Gentoo — Phase 3+4 Test Harness
# Tests desktop environment configuration, GPU detection logic,
# optional package categories, overlay ebuild availability,
# Cold Canon structure, and knowledge infrastructure.
#
# Runs against the qcow2 disk prepared by test-phase0 + test-phase1
# Usage: sudo ./test-phase3-4.sh
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="${TEST_DIR}/../installer-gentoo"
QCOW2="${TEST_DIR}/logos-test.qcow2"
NBD_DEV="/dev/nbd0"
LUKS_PASS="REDACTED_PASS"
MNT="/mnt/logos-test"
PASS=0; FAIL=0

pass() { echo -e "\e[32m  PASS: $*\e[0m"; ((PASS++)) || true; }
fail() { echo -e "\e[31m  FAIL: $*\e[0m"; ((FAIL++)) || true; }

cleanup() {
  echo ""; echo "== Cleaning up =="
  umount -R "${MNT}" 2>/dev/null || true
  cryptsetup close logos-test-crypt 2>/dev/null || true
  sleep 1
  qemu-nbd --disconnect "${NBD_DEV}" 2>/dev/null || true
  echo "Done."
}
trap cleanup EXIT

[[ "${EUID}" -eq 0 ]] || { echo "Run as root"; exit 1; }

# ── Reconnect ────────────────────────────────────────────────────
echo ""; echo "== Reconnecting to test disk =="
modprobe nbd max_part=8 2>/dev/null || true
qemu-nbd --disconnect "${NBD_DEV}" 2>/dev/null || true
sleep 1
qemu-nbd --connect="${NBD_DEV}" "${QCOW2}"
sleep 2

echo -n "${LUKS_PASS}" | cryptsetup open "${NBD_DEV}p3" logos-test-crypt -
BTRFS_OPTS="noatime,compress=zstd:3,space_cache=v2"
mkdir -p "${MNT}"
mount -o "subvol=@,${BTRFS_OPTS}" /dev/mapper/logos-test-crypt "${MNT}"
mkdir -p "${MNT}"/{boot,var/log,home}
mount "${NBD_DEV}p2" "${MNT}/boot"
mkdir -p "${MNT}/boot/efi"
mount "${NBD_DEV}p1" "${MNT}/boot/efi"
mount -o "subvol=@log,${BTRFS_OPTS}" /dev/mapper/logos-test-crypt "${MNT}/var/log"
mount -o "subvol=@home,${BTRFS_OPTS}" /dev/mapper/logos-test-crypt "${MNT}/home"
pass "Disk remounted (with @home)"

# ═══════════════════════════════════════════════════════════════════
# TEST SECTION 1: Phase 3 Script Structure
# ═══════════════════════════════════════════════════════════════════
echo ""; echo "== Phase 3 Script Structure =="

P3="${INSTALLER_DIR}/phase3-desktop.sh"
[[ -f "${P3}" ]] && pass "phase3-desktop.sh exists" || fail "phase3-desktop.sh missing"
bash -n "${P3}" 2>/dev/null && pass "phase3: valid bash syntax" || fail "phase3: syntax error"

# Verify shebang and safety
head -3 "${P3}" | grep -q '#!/usr/bin/env bash' && pass "phase3: correct shebang" || fail "phase3: wrong shebang"
grep -q 'set -euo pipefail' "${P3}" && pass "phase3: strict error handling" || fail "phase3: no strict mode"
grep -q 'require_root' "${P3}" && pass "phase3: requires root" || fail "phase3: no root check"

# Verify sourcing
grep -q 'source.*lib/common.sh' "${P3}" && pass "phase3: sources common.sh" || fail "phase3: no common.sh"
grep -q 'source.*lib/portage.sh' "${P3}" && pass "phase3: sources portage.sh" || fail "phase3: no portage.sh"

# ═══════════════════════════════════════════════════════════════════
# TEST SECTION 2: KDE Plasma Desktop Packages
# ═══════════════════════════════════════════════════════════════════
echo ""; echo "== KDE Plasma Desktop =="

grep -q 'kde-plasma/plasma-meta' "${P3}" && pass "KDE: plasma-meta" || fail "KDE: no plasma-meta"
grep -q 'x11-misc/sddm'         "${P3}" && pass "KDE: sddm"        || fail "KDE: no sddm"
grep -q 'kde-apps/kde-apps-meta' "${P3}" && pass "KDE: apps-meta"   || fail "KDE: no apps-meta"
grep -q 'systemctl enable sddm'  "${P3}" && pass "KDE: sddm enabled" || fail "KDE: sddm not enabled"

# ═══════════════════════════════════════════════════════════════════
# TEST SECTION 3: GPU Auto-Detection Logic
# ═══════════════════════════════════════════════════════════════════
echo ""; echo "== GPU Auto-Detection =="

# NVIDIA detection
grep -q 'lspci.*nvidia'               "${P3}" && pass "GPU: NVIDIA detection"        || fail "GPU: no NVIDIA detect"
grep -q 'x11-drivers/nvidia-drivers'   "${P3}" && pass "GPU: NVIDIA driver package"   || fail "GPU: no nvidia-drivers"
grep -q 'VIDEO_CARDS.*nvidia'          "${P3}" && pass "GPU: NVIDIA VIDEO_CARDS"      || fail "GPU: no NVIDIA VIDEO_CARDS"

# AMD detection
grep -q 'lspci.*amd\|radeon\|amdgpu'   "${P3}" && pass "GPU: AMD detection"          || fail "GPU: no AMD detect"
grep -q 'xf86-video-amdgpu'            "${P3}" && pass "GPU: AMD driver package"      || fail "GPU: no amdgpu driver"
grep -q 'VIDEO_CARDS.*amdgpu'           "${P3}" && pass "GPU: AMD VIDEO_CARDS"         || fail "GPU: no AMD VIDEO_CARDS"

# Intel detection
grep -q 'lspci.*intel.*vga\|intel.*graphics' "${P3}" && pass "GPU: Intel detection"   || fail "GPU: no Intel detect"
grep -q 'intel-media-driver'            "${P3}" && pass "GPU: Intel media driver"      || fail "GPU: no Intel driver"
grep -q 'VIDEO_CARDS.*intel'            "${P3}" && pass "GPU: Intel VIDEO_CARDS"       || fail "GPU: no Intel VIDEO_CARDS"

# Fallback
grep -q 'framebuffer'                   "${P3}" && pass "GPU: framebuffer fallback"    || fail "GPU: no fallback"
grep -q 'pciutils'                      "${P3}" && pass "GPU: pciutils dependency"     || fail "GPU: no pciutils"

# ═══════════════════════════════════════════════════════════════════
# TEST SECTION 4: Optional Package Categories (env-var gated)
# ═══════════════════════════════════════════════════════════════════
echo ""; echo "== Optional Package Categories =="

# Verify all 10 categories are env-var gated
CATEGORIES=("INSTALL_OFFICE" "INSTALL_ENGINEERING" "INSTALL_DEV" "INSTALL_SECURITY"
            "INSTALL_RADIO" "INSTALL_GAMING" "INSTALL_MEDIA"
            "INSTALL_SDR" "INSTALL_SPECTRAL" "INSTALL_RUST_TOOLS")
for cat in "${CATEGORIES[@]}"; do
  grep -q "${cat}" "${P3}" && pass "Category gated: ${cat}" || fail "Category missing: ${cat}"
done

# Validate key packages in each category
echo ""; echo "== Category Package Validation =="

# Office
grep -q 'app-office/libreoffice'     "${P3}" && pass "Office: libreoffice"     || fail "Office: no libreoffice"
grep -q 'www-client/firefox'         "${P3}" && pass "Office: firefox"         || fail "Office: no firefox"
grep -q 'mail-client/thunderbird'    "${P3}" && pass "Office: thunderbird"     || fail "Office: no thunderbird"
grep -q 'app-misc/obsidian-bin'      "${P3}" && pass "Office: obsidian-bin (overlay)" || fail "Office: no obsidian"

# Engineering
grep -q 'media-gfx/freecad'         "${P3}" && pass "Engineering: freecad"    || fail "Engineering: no freecad"
grep -q 'sci-electronics/kicad'      "${P3}" && pass "Engineering: kicad"      || fail "Engineering: no kicad"
grep -q 'media-gfx/blender'         "${P3}" && pass "Engineering: blender"    || fail "Engineering: no blender"

# Dev
grep -q 'dev-vcs/git'               "${P3}" && pass "Dev: git"               || fail "Dev: no git"
grep -q 'app-containers/docker'      "${P3}" && pass "Dev: docker"            || fail "Dev: no docker"
grep -q 'systemctl enable docker'    "${P3}" && pass "Dev: docker enabled"    || fail "Dev: docker not enabled"
grep -q 'usermod -aG docker'        "${P3}" && pass "Dev: docker user group"  || fail "Dev: no docker group"

# Security
grep -q 'net-analyzer/wireshark'     "${P3}" && pass "Security: wireshark"    || fail "Security: no wireshark"
grep -q 'net-analyzer/nmap'          "${P3}" && pass "Security: nmap"         || fail "Security: no nmap"
grep -q 'app-crypt/hashcat'         "${P3}" && pass "Security: hashcat"      || fail "Security: no hashcat"
grep -q 'net-analyzer/metasploit'    "${P3}" && pass "Security: metasploit (overlay)" || fail "Security: no metasploit"
grep -q 'net-analyzer/shannon'       "${P3}" && pass "Security: shannon (overlay)"    || fail "Security: no shannon"
grep -q 'pentoo'                     "${P3}" && pass "Security: pentoo overlay"       || fail "Security: no pentoo"

# Radio
grep -q 'net-wireless/gnuradio'      "${P3}" && pass "Radio: gnuradio"        || fail "Radio: no gnuradio"
grep -q 'net-wireless/gqrx'          "${P3}" && pass "Radio: gqrx"            || fail "Radio: no gqrx"

# Gaming
grep -q 'games-util/steam-launcher'  "${P3}" && pass "Gaming: steam"          || fail "Gaming: no steam"
grep -q 'app-emulation/wine'         "${P3}" && pass "Gaming: wine"           || fail "Gaming: no wine"
grep -q 'games-util/gamemode'        "${P3}" && pass "Gaming: gamemode"       || fail "Gaming: no gamemode"

# Media
grep -q 'media-video/vlc'           "${P3}" && pass "Media: vlc"             || fail "Media: no vlc"
grep -q 'media-video/obs-studio'     "${P3}" && pass "Media: obs-studio"      || fail "Media: no obs"
grep -q 'media-gfx/gimp'            "${P3}" && pass "Media: gimp"            || fail "Media: no gimp"

# SDR (extended)
grep -q 'net-wireless/rtl-sdr'       "${P3}" && pass "SDR: rtl-sdr"           || fail "SDR: no rtl-sdr"
grep -q 'net-wireless/hackrf-tools'  "${P3}" && pass "SDR: hackrf-tools"      || fail "SDR: no hackrf"
grep -q 'net-wireless/soapysdr'      "${P3}" && pass "SDR: soapysdr"          || fail "SDR: no soapysdr"
grep -q 'net-wireless/sdrangel'      "${P3}" && pass "SDR: sdrangel (overlay)" || fail "SDR: no sdrangel"

# Spectral
grep -q 'sci-libs/fftw'             "${P3}" && pass "Spectral: fftw"         || fail "Spectral: no fftw"
grep -q 'dev-python/scipy'          "${P3}" && pass "Spectral: scipy"        || fail "Spectral: no scipy"
grep -q 'dev-python/numpy'          "${P3}" && pass "Spectral: numpy"        || fail "Spectral: no numpy"
grep -q 'media-sound/sonic-visualiser' "${P3}" && pass "Spectral: sonic-visualiser" || fail "Spectral: no sonic-vis"

# Rust tools
grep -q 'sys-apps/ripgrep'          "${P3}" && pass "Rust: ripgrep"          || fail "Rust: no ripgrep"
grep -q 'sys-apps/fd'               "${P3}" && pass "Rust: fd"               || fail "Rust: no fd"
grep -q 'sys-apps/bat'              "${P3}" && pass "Rust: bat"              || fail "Rust: no bat"
grep -q 'app-misc/eza'              "${P3}" && pass "Rust: eza"              || fail "Rust: no eza"
grep -q 'sys-process/bottom'         "${P3}" && pass "Rust: bottom"           || fail "Rust: no bottom"
grep -q 'app-shells/starship'        "${P3}" && pass "Rust: starship"         || fail "Rust: no starship"
grep -q 'dev-util/tokei'            "${P3}" && pass "Rust: tokei"            || fail "Rust: no tokei"
grep -q 'sys-apps/dust'             "${P3}" && pass "Rust: dust"             || fail "Rust: no dust"
grep -q 'app-shells/zoxide'          "${P3}" && pass "Rust: zoxide"           || fail "Rust: no zoxide"
grep -q 'net-analyzer/bandwhich'     "${P3}" && pass "Rust: bandwhich"        || fail "Rust: no bandwhich"
grep -q 'sys-process/procs'          "${P3}" && pass "Rust: procs"            || fail "Rust: no procs"

# ═══════════════════════════════════════════════════════════════════
# TEST SECTION 5: Overlay Ebuild Availability
# ═══════════════════════════════════════════════════════════════════
echo ""; echo "== Overlay Ebuild Verification =="

OVERLAY="${INSTALLER_DIR}/overlays/logos-overlay"

# Check overlay structure
[[ -f "${OVERLAY}/metadata/layout.conf" ]] && pass "Overlay: layout.conf exists" || fail "Overlay: no layout.conf"
[[ -f "${OVERLAY}/profiles/repo_name" ]]   && pass "Overlay: repo_name exists"   || fail "Overlay: no repo_name"

REPO_NAME="$(cat "${OVERLAY}/profiles/repo_name")"
[[ "${REPO_NAME}" == "logos-overlay" ]] && pass "Overlay: repo_name=logos-overlay" || fail "Overlay: wrong repo_name (${REPO_NAME})"

grep -q 'masters = gentoo' "${OVERLAY}/metadata/layout.conf" && pass "Overlay: masters=gentoo" || fail "Overlay: wrong masters"

# Verify all 5 ebuilds referenced in phase3/phase4 exist
EBUILDS=(
  "net-wireless/sdrangel/sdrangel-7.23.1.ebuild"
  "app-misc/obsidian-bin/obsidian-bin-1.11.7.ebuild"
  "app-misc/kiwix-tools/kiwix-tools-3.8.1.ebuild"
  "app-misc/kiwix-desktop/kiwix-desktop-2.5.1.ebuild"
  "net-analyzer/shannon/shannon-0.1.0.ebuild"
)
for eb in "${EBUILDS[@]}"; do
  [[ -f "${OVERLAY}/${eb}" ]] && pass "Ebuild: ${eb}" || fail "Ebuild missing: ${eb}"
done

# Validate ebuild EAPI
for eb in "${EBUILDS[@]}"; do
  if [[ -f "${OVERLAY}/${eb}" ]]; then
    grep -q 'EAPI=8' "${OVERLAY}/${eb}" && pass "EAPI 8: $(basename "${eb}")" || fail "Wrong EAPI: $(basename "${eb}")"
  fi
done

# Validate ebuild LICENSE fields
grep -q 'LICENSE="GPL-3"'  "${OVERLAY}/net-wireless/sdrangel/sdrangel-7.23.1.ebuild" && pass "sdrangel: GPL-3 license" || fail "sdrangel: wrong license"
grep -q 'LICENSE="Obsidian' "${OVERLAY}/app-misc/obsidian-bin/obsidian-bin-1.11.7.ebuild" && pass "obsidian: Obsidian license" || fail "obsidian: wrong license"
grep -q 'LICENSE="GPL-3"'   "${OVERLAY}/app-misc/kiwix-tools/kiwix-tools-3.8.1.ebuild" && pass "kiwix-tools: GPL-3 license" || fail "kiwix-tools: wrong license"
grep -q 'LICENSE="GPL-3"'   "${OVERLAY}/app-misc/kiwix-desktop/kiwix-desktop-2.5.1.ebuild" && pass "kiwix-desktop: GPL-3 license" || fail "kiwix-desktop: wrong license"
grep -q 'LICENSE="AGPL-3"'  "${OVERLAY}/net-analyzer/shannon/shannon-0.1.0.ebuild" && pass "shannon: AGPL-3 license" || fail "shannon: wrong license"

# Validate SDRangel USE flags (hardware support)
SDRANGEL="${OVERLAY}/net-wireless/sdrangel/sdrangel-7.23.1.ebuild"
for flag in airspy bladerf hackrf limesuite plutosdr rtlsdr soapy uhd; do
  grep -q "${flag}" "${SDRANGEL}" && pass "sdrangel USE: ${flag}" || fail "sdrangel USE missing: ${flag}"
done

# Validate Shannon is Docker-based
SHANNON="${OVERLAY}/net-analyzer/shannon/shannon-0.1.0.ebuild"
grep -q 'docker\|Docker' "${SHANNON}" && pass "shannon: Docker-based" || fail "shannon: not Docker"
grep -q 'ANTHROPIC_API_KEY' "${SHANNON}" && pass "shannon: requires API key" || fail "shannon: no API key ref"

# Deploy overlay to test filesystem
echo ""; echo "== Deploying overlay to test filesystem =="
OVERLAY_DST="${MNT}/var/db/repos/logos-overlay"
mkdir -p "${OVERLAY_DST}"
cp -a "${OVERLAY}/." "${OVERLAY_DST}/"
[[ -d "${OVERLAY_DST}/net-wireless/sdrangel" ]] && pass "Overlay deployed: sdrangel" || fail "Overlay deploy: sdrangel"
[[ -d "${OVERLAY_DST}/app-misc/obsidian-bin" ]] && pass "Overlay deployed: obsidian" || fail "Overlay deploy: obsidian"
[[ -d "${OVERLAY_DST}/net-analyzer/shannon" ]]  && pass "Overlay deployed: shannon"  || fail "Overlay deploy: shannon"

# ═══════════════════════════════════════════════════════════════════
# TEST SECTION 6: Phase 4 Script Structure
# ═══════════════════════════════════════════════════════════════════
echo ""; echo "== Phase 4 Script Structure =="

P4="${INSTALLER_DIR}/phase4-knowledge.sh"
[[ -f "${P4}" ]] && pass "phase4-knowledge.sh exists" || fail "phase4-knowledge.sh missing"
bash -n "${P4}" 2>/dev/null && pass "phase4: valid bash syntax" || fail "phase4: syntax error"
head -3 "${P4}" | grep -q '#!/usr/bin/env bash' && pass "phase4: correct shebang" || fail "phase4: wrong shebang"
grep -q 'set -euo pipefail' "${P4}" && pass "phase4: strict error handling" || fail "phase4: no strict mode"
grep -q 'require_root' "${P4}" && pass "phase4: requires root" || fail "phase4: no root check"
grep -q 'source.*lib/common.sh' "${P4}" && pass "phase4: sources common.sh" || fail "phase4: no common.sh"
grep -q 'source.*lib/portage.sh' "${P4}" && pass "phase4: sources portage.sh" || fail "phase4: no portage.sh"

# ═══════════════════════════════════════════════════════════════════
# TEST SECTION 7: Cold Canon Directory Structure
# ═══════════════════════════════════════════════════════════════════
echo ""; echo "== Cold Canon Structure =="

# Validate script creates correct dirs
grep -q '/srv/cold-canon' "${P4}" && pass "Canon: cold-canon path" || fail "Canon: no cold-canon"
grep -q '/srv/warm-mesh'  "${P4}" && pass "Canon: warm-mesh path"  || fail "Canon: no warm-mesh"
grep -q '/srv/hot-workspace' "${P4}" && pass "Canon: hot-workspace path" || fail "Canon: no hot-workspace"

# Subdirectories
grep -q 'documents' "${P4}" && pass "Canon: documents subdir"  || fail "Canon: no documents"
grep -q 'software'  "${P4}" && pass "Canon: software subdir"   || fail "Canon: no software"
grep -q 'datasets'  "${P4}" && pass "Canon: datasets subdir"   || fail "Canon: no datasets"
grep -q 'media'     "${P4}" && pass "Canon: media subdir"      || fail "Canon: no media"

# Permissions
grep -q 'chown.*root:wheel.*/srv/cold-canon' "${P4}" && pass "Canon: cold-canon ownership" || fail "Canon: no cold ownership"
grep -q 'chmod.*750.*/srv/cold-canon'         "${P4}" && pass "Canon: cold-canon perms 750" || fail "Canon: wrong cold perms"
grep -q 'chmod.*770.*/srv/warm-mesh'          "${P4}" && pass "Canon: warm-mesh perms 770"  || fail "Canon: wrong warm perms"

# Simulate Canon creation on test filesystem
mkdir -p "${MNT}/srv/cold-canon"/{documents,software,datasets,media}
mkdir -p "${MNT}/srv/warm-mesh"
mkdir -p "${MNT}/srv/hot-workspace"
[[ -d "${MNT}/srv/cold-canon/documents" ]] && pass "Canon: documents created"  || fail "Canon: documents failed"
[[ -d "${MNT}/srv/cold-canon/software" ]]  && pass "Canon: software created"   || fail "Canon: software failed"
[[ -d "${MNT}/srv/cold-canon/datasets" ]]  && pass "Canon: datasets created"   || fail "Canon: datasets failed"
[[ -d "${MNT}/srv/cold-canon/media" ]]     && pass "Canon: media created"      || fail "Canon: media failed"
[[ -d "${MNT}/srv/warm-mesh" ]]            && pass "Canon: warm-mesh created"  || fail "Canon: warm-mesh failed"
[[ -d "${MNT}/srv/hot-workspace" ]]        && pass "Canon: hot-workspace created" || fail "Canon: hot-workspace failed"

# ═══════════════════════════════════════════════════════════════════
# TEST SECTION 8: Ollama Integration
# ═══════════════════════════════════════════════════════════════════
echo ""; echo "== Ollama Integration =="

# Verify distro-agnostic installer (not emerge)
grep -q 'curl.*ollama.com/install.sh' "${P4}" && pass "Ollama: curl installer" || fail "Ollama: no curl install"
grep -q 'INSTALL_OLLAMA'              "${P4}" && pass "Ollama: env-var gated"  || fail "Ollama: not gated"
grep -q 'systemctl enable ollama'     "${P4}" && pass "Ollama: service enabled" || fail "Ollama: not enabled"
grep -q 'ollama pull'                 "${P4}" && pass "Ollama: model pulls"    || fail "Ollama: no pulls"

# Verify recommended models
grep -q 'llama3'  "${P4}" && pass "Ollama: llama3 model"  || fail "Ollama: no llama3"
grep -q 'qwen2'   "${P4}" && pass "Ollama: qwen2 model"   || fail "Ollama: no qwen2"
grep -q 'mistral' "${P4}" && pass "Ollama: mistral model" || fail "Ollama: no mistral"

# ═══════════════════════════════════════════════════════════════════
# TEST SECTION 9: Kiwix Integration
# ═══════════════════════════════════════════════════════════════════
echo ""; echo "== Kiwix Integration =="

grep -q 'INSTALL_KIWIX'          "${P4}" && pass "Kiwix: env-var gated"     || fail "Kiwix: not gated"
grep -q 'app-misc/kiwix-tools'   "${P4}" && pass "Kiwix: kiwix-tools"      || fail "Kiwix: no kiwix-tools"
grep -q 'app-misc/kiwix-desktop' "${P4}" && pass "Kiwix: kiwix-desktop"    || fail "Kiwix: no kiwix-desktop"
grep -q 'install_logos_overlay'  "${P4}" && pass "Kiwix: from logos-overlay" || fail "Kiwix: not from overlay"

# ═══════════════════════════════════════════════════════════════════
# TEST SECTION 10: Tool Installation Logic
# ═══════════════════════════════════════════════════════════════════
echo ""; echo "== Tool Installation Logic =="

# Verify both tool paths
grep -q 'logos-assist'        "${P4}" && pass "Tools: logos-assist referenced"        || fail "Tools: no logos-assist"
grep -q 'logos-canon-promote' "${P4}" && pass "Tools: logos-canon-promote referenced" || fail "Tools: no logos-canon-promote"

# TARGET_USER conditional
grep -q 'TARGET_USER'          "${P4}" && pass "Tools: TARGET_USER conditional"  || fail "Tools: no TARGET_USER"
grep -q '\.local/bin'          "${P4}" && pass "Tools: user-local install path"  || fail "Tools: no local path"
grep -q '/usr/local/bin'       "${P4}" && pass "Tools: system-wide fallback"     || fail "Tools: no system path"
grep -q 'getent passwd'        "${P4}" && pass "Tools: home dir resolution"      || fail "Tools: no home resolution"

# Simulate tool installation to test filesystem
install -Dm755 "${INSTALLER_DIR}/tools/logos-assist" "${MNT}/usr/local/bin/logos-assist"
install -Dm755 "${INSTALLER_DIR}/tools/logos-canon-promote" "${MNT}/usr/local/bin/logos-canon-promote"
[[ -x "${MNT}/usr/local/bin/logos-assist" ]]        && pass "Tools: logos-assist deployed"        || fail "Tools: assist deploy failed"
[[ -x "${MNT}/usr/local/bin/logos-canon-promote" ]]  && pass "Tools: logos-canon-promote deployed" || fail "Tools: promote deploy failed"

# Simulate user-local install
TEST_USER_HOME="${MNT}/home/testuser"
mkdir -p "${TEST_USER_HOME}/.local/bin"
install -m 0755 "${INSTALLER_DIR}/tools/logos-assist" "${TEST_USER_HOME}/.local/bin/logos-assist"
install -m 0755 "${INSTALLER_DIR}/tools/logos-canon-promote" "${TEST_USER_HOME}/.local/bin/logos-canon-promote"
[[ -x "${TEST_USER_HOME}/.local/bin/logos-assist" ]]        && pass "Tools: user-local logos-assist"        || fail "Tools: user-local assist failed"
[[ -x "${TEST_USER_HOME}/.local/bin/logos-canon-promote" ]]  && pass "Tools: user-local logos-canon-promote" || fail "Tools: user-local promote failed"

# ═══════════════════════════════════════════════════════════════════
# TEST SECTION 11: Cross-Phase Integration
# ═══════════════════════════════════════════════════════════════════
echo ""; echo "== Cross-Phase Integration =="

# Verify phase3 references logos-overlay install function
grep -q 'install_logos_overlay' "${P3}" && pass "Phase3: calls install_logos_overlay" || fail "Phase3: no overlay install"

# Verify pentoo overlay setup in security category
grep -q 'ensure_eselect_repository' "${P3}" && pass "Phase3: uses eselect-repository" || fail "Phase3: no eselect-repository"
grep -q 'add_overlay.*pentoo' "${P3}" && pass "Phase3: adds pentoo overlay" || fail "Phase3: no pentoo add"

# Verify phase4 references install_logos_overlay for kiwix
grep -q 'install_logos_overlay' "${P4}" && pass "Phase4: calls install_logos_overlay" || fail "Phase4: no overlay install"

# Verify all lib files have valid syntax
for lib in common.sh portage.sh uuid.sh; do
  bash -n "${INSTALLER_DIR}/lib/${lib}" 2>/dev/null && pass "Lib syntax: ${lib}" || fail "Lib syntax error: ${lib}"
done

# Verify all phase scripts have valid syntax
for phase in phase0-partition.sh phase1-stage3.sh phase2-transform.sh phase3-desktop.sh phase4-knowledge.sh; do
  bash -n "${INSTALLER_DIR}/${phase}" 2>/dev/null && pass "Phase syntax: ${phase}" || fail "Phase syntax error: ${phase}"
done

# Verify portage.sh has all functions phase3/phase4 need
PORTAGE="${INSTALLER_DIR}/lib/portage.sh"
grep -q 'emerge_pkgs()'            "${PORTAGE}" && pass "portage.sh: emerge_pkgs() defined"     || fail "portage.sh: no emerge_pkgs"
grep -q 'add_overlay()'            "${PORTAGE}" && pass "portage.sh: add_overlay() defined"     || fail "portage.sh: no add_overlay"
grep -q 'install_logos_overlay()'  "${PORTAGE}" && pass "portage.sh: install_logos_overlay()"   || fail "portage.sh: no install_logos_overlay"
grep -q 'ensure_eselect_repository()' "${PORTAGE}" && pass "portage.sh: ensure_eselect_repository()" || fail "portage.sh: no ensure_eselect"

# ═══════════════════════════════════════════════════════════════════
# TEST SECTION 12: Filesystem State Verification
# ═══════════════════════════════════════════════════════════════════
echo ""; echo "== Filesystem State (cumulative) =="

# All critical directories from phases 0-4 should exist
CRITICAL_DIRS=(
  "boot" "boot/efi" "boot/grub" "etc" "etc/portage"
  "etc/sysctl.d" "etc/audit/rules.d" "etc/ssh/sshd_config.d"
  "etc/dracut.conf.d" "etc/grub.d" "etc/systemd/system"
  "usr/local/bin" "usr/local/lib/logos"
  "srv/cold-canon" "srv/cold-canon/documents" "srv/cold-canon/software"
  "srv/cold-canon/datasets" "srv/cold-canon/media"
  "srv/warm-mesh" "srv/hot-workspace"
  "var/db/repos/logos-overlay"
)
for d in "${CRITICAL_DIRS[@]}"; do
  [[ -d "${MNT}/${d}" ]] && pass "Dir exists: /${d}" || fail "Dir missing: /${d}"
done

# Critical files from all phases
CRITICAL_FILES=(
  "etc/logos-release"
  "etc/default/grub"
  "etc/grub.d/41_logos_profiles"
  "etc/sysctl.d/99-logos-hardening.conf"
  "etc/audit/rules.d/logos-audit.rules"
  "etc/ssh/sshd_config.d/10-logos-ssh.conf"
  "etc/dracut.conf.d/logos.conf"
  "etc/systemd/system/logos-kernel-watchdog.service"
  "etc/systemd/system/logos-kernel-watchdog.timer"
  "usr/local/bin/logos-validate-boot"
  "usr/local/bin/logos-assist"
  "usr/local/bin/logos-canon-promote"
  "usr/local/lib/logos/kernel-watchdog.sh"
)
for f in "${CRITICAL_FILES[@]}"; do
  [[ -f "${MNT}/${f}" ]] && pass "File exists: /${f}" || fail "File missing: /${f}"
done

# ── Summary ───────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "  Phase 3+4 Test Results"
echo "  PASS: ${PASS}  FAIL: ${FAIL}"
echo "========================================"

cat > "${TEST_DIR}/test-phase3-4-results.log" << REOF
Phase 3+4 Test — $(date -Iseconds)
PASS: ${PASS}
FAIL: ${FAIL}
Sections tested:
  1. Phase 3 script structure (shebang, safety, sourcing)
  2. KDE Plasma desktop packages
  3. GPU auto-detection logic (NVIDIA, AMD, Intel, fallback)
  4. Optional package categories (10 env-var gated)
  5. Overlay ebuild availability (5 ebuilds, EAPI, licenses, USE flags)
  6. Phase 4 script structure
  7. Cold Canon directory structure (topology, permissions)
  8. Ollama integration (installer, models, service)
  9. Kiwix integration (overlay packages)
  10. Tool installation logic (user-local, system-wide)
  11. Cross-phase integration (lib functions, syntax validation)
  12. Filesystem state verification (cumulative all phases)
REOF

[[ "${FAIL}" -gt 0 ]] && exit 1 || exit 0
