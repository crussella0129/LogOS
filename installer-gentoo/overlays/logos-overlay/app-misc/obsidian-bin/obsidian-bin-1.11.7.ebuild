# Copyright 2026 LogOS Authors
# Distributed under the terms of the Obsidian EULA

EAPI=8

DESCRIPTION="Markdown-based knowledge base and note-taking application"
HOMEPAGE="https://obsidian.md"
SRC_URI="https://github.com/obsidianmd/obsidian-releases/releases/download/v${PV}/obsidian-${PV}.tar.gz"

LICENSE="Obsidian-EULA"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="bindist mirror strip"

RDEPEND="
	x11-libs/gtk+:3
	dev-libs/nss
	media-libs/alsa-lib
	x11-libs/libnotify
	x11-misc/xdg-utils
	dev-libs/libappindicator:3
	app-accessibility/at-spi2-core:2
	x11-libs/libXtst
	x11-libs/libXScrnSaver
	sys-libs/glibc
	media-libs/mesa
"

S="${WORKDIR}/obsidian-${PV}"

QA_PREBUILT="opt/obsidian/*"

src_install() {
	insinto /opt/obsidian
	doins -r .

	fperms 0755 /opt/obsidian/obsidian
	fperms 0755 /opt/obsidian/chrome-sandbox

	dosym ../../opt/obsidian/obsidian /usr/bin/obsidian

	# Desktop entry
	cat > "${T}/obsidian.desktop" <<-EOF
	[Desktop Entry]
	Name=Obsidian
	Exec=obsidian %U
	Icon=obsidian
	Type=Application
	Categories=Office;TextEditor;
	MimeType=x-scheme-handler/obsidian;
	StartupWMClass=obsidian
	EOF
	insinto /usr/share/applications
	doins "${T}/obsidian.desktop"

	# Icons
	local size
	for size in 16 24 32 48 64 128 256 512; do
		if [[ -f "usr/share/icons/hicolor/${size}x${size}/apps/obsidian.png" ]]; then
			insinto "/usr/share/icons/hicolor/${size}x${size}/apps"
			doins "usr/share/icons/hicolor/${size}x${size}/apps/obsidian.png"
		fi
	done
}
