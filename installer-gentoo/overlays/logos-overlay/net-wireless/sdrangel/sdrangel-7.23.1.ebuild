# Copyright 2026 LogOS Authors
# Distributed under the terms of the GNU General Public License v3

EAPI=8

inherit cmake xdg-utils

DESCRIPTION="Open source SDR and signal analyzer frontend"
HOMEPAGE="https://github.com/f4exb/sdrangel"
SRC_URI="https://github.com/f4exb/${PN}/archive/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="~amd64"
IUSE="airspy bladerf hackrf limesuite plutosdr rtlsdr soapy uhd +gui server"

RDEPEND="
	dev-libs/boost:=
	sci-libs/fftw:3.0[float]
	dev-libs/libusb:1
	dev-libs/cm256cc
	media-libs/codec2
	dev-qt/qtcore:5
	dev-qt/qtwidgets:5
	dev-qt/qtwebsockets:5
	dev-qt/qtmultimedia:5
	dev-qt/qtserialport:5
	dev-qt/qtcharts:5
	dev-qt/qtpositioning:5
	gui? (
		dev-qt/qtopengl:5
		dev-qt/qtquickcontrols2:5
		dev-qt/qttexttospeech:5
		dev-qt/qtsvg:5
		dev-qt/qtwebengine:5
		virtual/opengl
	)
	airspy? ( net-wireless/airspy )
	bladerf? ( net-wireless/bladerf:= )
	hackrf? ( net-wireless/hackrf-tools:= )
	limesuite? ( net-wireless/limesuite )
	plutosdr? ( net-libs/libiio )
	rtlsdr? ( net-wireless/rtl-sdr )
	soapy? ( net-wireless/soapysdr:= )
	uhd? ( net-wireless/uhd:= )
	media-video/ffmpeg:=
	sys-libs/zlib
"

DEPEND="${RDEPEND}"

BDEPEND="
	virtual/pkgconfig
	dev-util/cmake
"

src_configure() {
	local mycmakeargs=(
		-DBUILD_GUI=$(usex gui ON OFF)
		-DBUILD_SERVER=$(usex server ON OFF)
		-DENABLE_AIRSPY=$(usex airspy ON OFF)
		-DENABLE_BLADERF=$(usex bladerf ON OFF)
		-DENABLE_HACKRF=$(usex hackrf ON OFF)
		-DENABLE_LIMESUITE=$(usex limesuite ON OFF)
		-DENABLE_IIO=$(usex plutosdr ON OFF)
		-DENABLE_RTLSDR=$(usex rtlsdr ON OFF)
		-DENABLE_SOAPYSDR=$(usex soapy ON OFF)
		-DENABLE_USRP=$(usex uhd ON OFF)
	)
	cmake_src_configure
}

pkg_postinst() {
	xdg_desktop_database_update
	xdg_icon_cache_update
}

pkg_postrm() {
	xdg_desktop_database_update
	xdg_icon_cache_update
}
