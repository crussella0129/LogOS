# Copyright 2026 LogOS Authors
# Distributed under the terms of the GNU Affero General Public License v3

EAPI=8

DESCRIPTION="Autonomous AI penetration tester (Docker-deployed)"
HOMEPAGE="https://github.com/KeygraphHQ/shannon"

# Shannon is deployed via Docker — this ebuild installs the launcher and deps
SRC_URI="https://github.com/KeygraphHQ/${PN}/archive/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="AGPL-3"
SLOT="0"
KEYWORDS="~amd64"

# Shannon runs inside Docker containers with Temporal orchestration
RDEPEND="
	app-containers/docker
	app-containers/docker-compose
	dev-vcs/git
"

# No build dependencies — TypeScript app runs in containers
BDEPEND=""

S="${WORKDIR}/${P}"

src_compile() {
	:  # Nothing to compile — container-based
}

src_install() {
	# Install source tree for Docker-based execution
	insinto "/opt/${PN}"
	doins -r .

	# Create launcher script
	cat > "${T}/shannon" <<-'EOF'
	#!/usr/bin/env bash
	# Shannon — Autonomous AI Penetration Tester
	# Requires: ANTHROPIC_API_KEY environment variable
	set -euo pipefail
	SHANNON_HOME="/opt/shannon"
	if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
	    echo "Error: ANTHROPIC_API_KEY must be set" >&2
	    echo "Export your API key: export ANTHROPIC_API_KEY='sk-...'" >&2
	    exit 1
	fi
	cd "${SHANNON_HOME}"
	exec ./shannon "$@"
	EOF
	dobin "${T}/shannon"

	dodoc README.md
}

pkg_postinst() {
	elog "Shannon requires Docker and an Anthropic API key."
	elog "Set ANTHROPIC_API_KEY before running."
	elog ""
	elog "Usage: shannon start URL=https://target.com"
	elog ""
	elog "WARNING: Only use against systems you are authorized to test."
}
