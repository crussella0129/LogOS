# Copyright 2026 LogOS Authors
# Distributed under the terms of the GNU General Public License v3

EAPI=8

inherit meson

DESCRIPTION="Command line tools for Kiwix offline content server"
HOMEPAGE="https://github.com/kiwix/kiwix-tools"
SRC_URI="https://github.com/kiwix/${PN}/archive/${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="~amd64"

# libkiwix and libzim may need their own ebuilds
RDEPEND="
	>=dev-libs/libkiwix-14.1.0
	>=dev-libs/libzim-9.0.0
	dev-cpp/docopt
"

DEPEND="${RDEPEND}"

BDEPEND="
	virtual/pkgconfig
	>=dev-build/meson-0.56.0
"

src_configure() {
	local emesonargs=()
	meson_src_configure
}
