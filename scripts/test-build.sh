#!/bin/bash
## Build the binary packages of a source package made by build-source.sh,
##  to check a port locally before it is uploaded. It installs the build
##  dependencies, so run it as root in the container:
##  scripts/run-local.sh --root scripts/test-build.sh [--series <series>] <package>
##
##  --with <other>  install the binary packages built by test-build.sh for
##                  another package first (a build dependency in the PPA)
##
## The binary packages and the log are written to BUILD_DIR/<series>/<package>/binary/.

set -euo pipefail
source "$(dirname "$0")"/lib.sh

series=${SERIES[0]}
with=()
while [[ $# -gt 0 ]]; do
	case $1 in
		--series) series=$2; shift 2 ;;
		--with) with+=( "$2" ); shift 2 ;;
		*) break ;;
	esac
done
[[ $# -eq 1 ]] || die "Usage: $0 [--series <series>] <package>"
pkg=$1
[[ ${EUID} -eq 0 ]] || die "Run it as root (scripts/run-local.sh --root ...)."

base_dir="${BUILD_DIR:-${REPO_ROOT}/build}/${series}/${pkg}"
[[ -f ${base_dir}/result.env ]] || die "Run build-source.sh ${pkg} first."
source "${base_dir}"/result.env
[[ ${STATUS} == built ]] || die "${pkg} was not built (${STATUS})."

binary="${base_dir}/binary"
rm -rf "${binary}"
mkdir -p "${binary}"
dsc="${base_dir}/out/${SOURCE}_${VERSION#*:}.dsc"
dpkg-source --no-check -x "${dsc}" "${binary}"/tree >/dev/null

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
for other in "${with[@]}"; do
	debs=( "${BUILD_DIR:-${REPO_ROOT}/build}/${series}/${other}"/binary/*.deb )
	[[ -f ${debs[0]} ]] || die "Run test-build.sh ${other} first."
	einfo "Installing the packages of ${other}"
	apt-get install -y -qq "${debs[@]}" >/dev/null || die "Installing the packages of ${other} failed."
done
(cd "${binary}"/tree && apt-get build-dep -y -qq ./ >/dev/null) || die "Build dependencies can't be installed."

einfo "Building ${SOURCE} ${VERSION}"
(cd "${binary}"/tree && dpkg-buildpackage -b -us -uc) > "${binary}"/build.log 2>&1 \
	|| { tail -n 40 "${binary}"/build.log >&2; die "Build failed, see ${binary}/build.log."; }
rm -rf "${binary}"/tree
chown -R --reference="${base_dir}" "${binary}"
einfo "Binary packages in ${binary}:"
ls "${binary}"/*.deb >&2
