#!/bin/bash
## Print the packages as JSON: name, source package, group, local, the overlay
##  package (overlay_pkg), the Ubuntu source (ubuntu_src), whether the source is
##  derived from another one under its own name (derived), whether it comes
##  from an older series (older, with ubuntu_series) or from Debian
##  (debian_suite), HOLD (hold), the patches of PATCHES that the port has in
##  packages/<port>/patches (variants), which replace an overlay patch of the
##  same name, and the other overlay packages that it follows (follow,
##  OVERLAY_FOLLOW). With --input <overlay>, also print the input hash.

set -euo pipefail
source "$(dirname "$0")"/lib.sh

overlay=
[[ ${1:-} == --input ]] && overlay=$(realpath "$2")

{
	for pkg in $(list_packages); do
		load_package "${pkg}"
		input=
		[[ -n ${overlay} ]] && input=$(input_hash "${overlay}")
		variants=()
		for name in "${PATCHES[@]}"; do
			[[ -f ${PKG_DIR}/patches/${name} ]] && variants+=( "${name}" )
		done
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${pkg}" "${SOURCE_NAME}" "${GROUP:-}" \
			"${LOCAL:-}" "${input}" "${OVERLAY_PKG:-}" "${UBUNTU_SRC:-}" "${UBUNTU_SERIES:-}" \
			"${DEBIAN_SUITE:-}" "${HOLD:-}" "${variants[*]}" "${OVERLAY_FOLLOW[*]}"
	done
} | python3 -I -c '
import json, sys
rows = [line.rstrip("\n").split("\t") for line in sys.stdin]
print(json.dumps([{"name": r[0], "source": r[1], "group": r[2], "local": bool(r[3]),
                   "input": r[4], "overlay_pkg": r[5], "ubuntu_src": r[6],
                   "derived": bool(r[6]) and r[1] != r[6], "older": bool(r[7]),
                   "ubuntu_series": r[7], "debian_suite": r[8], "hold": r[9],
                   "variants": r[10].split(), "follow": r[11].split()} for r in rows]))'
