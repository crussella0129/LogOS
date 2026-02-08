# Copyright 2026 LogOS Authors
# Distributed under the terms of the GNU General Public License v3

EAPI=8

inherit qmake-utils xdg-utils

DESCRIPTION="Kiwix offline reader desktop application"
HOMEPAGE="https://github.com/kiwix/kiwix-desktop"
SRC_URI="https://github.com/kiwix/${PN}/archive/${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="~amd64"

RDEPEND="
	>=dev-libs/libkiwix-14.0.0
	>=dev-libs/libzim-9.0.0
	dev-qt/qtcore:5
	dev-qt/qtgui:5
	dev-qt/qtnetwork:5
	dev-qt/qtwidgets:5
	dev-qt/qtwebengine:5
	dev-qt/qtwebchannel:5
	dev-qt/qtprintsupport:5
"

DEPEND="${RDEPEND}"

BDEPEND="
	virtual/pkgconfig
	dev-qt/linguist-tools:5
"

src_configure() {
	eqmake5 ${PN}.pro
}

src_install() {
	emake INSTALL_ROOT="${D}" install
}

pkg_postinst() {
	xdg_desktop_database_update
	xdg_icon_cache_update
}

pkg_postrm() {
	xdg_desktop_database_update
	xdg_icon_cache_update
}
