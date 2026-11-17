#!/bin/bash
## Print the packages as JSON: name, source package, group, local, the overlay
##  package (overlay_pkg), the Ubuntu source (ubuntu_src), whether the source is
##  derived from another one under its own name (derived), and whether it comes
##  from an older series (older). With --input <overlay>, also print the input
##  hash.

set -euo pipefail
source "$(dirname "$0")"/lib.sh

overlay=
[[ ${1:-} == --input ]] && overlay=$(realpath "$2")

{
	for pkg in $(list_packages); do
		load_package "${pkg}"
		input=
		[[ -n ${overlay} ]] && input=$(input_hash "${overlay}")
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${pkg}" "${SOURCE_NAME}" "${GROUP:-}" "${LOCAL:-}" \
			"${input}" "${OVERLAY_PKG:-}" "${UBUNTU_SRC:-}" "${UBUNTU_SERIES:-}"
	done
} | python3 -I -c '
import json, sys
rows = [line.rstrip("\n").split("\t") for line in sys.stdin]
print(json.dumps([{"name": r[0], "source": r[1], "group": r[2], "local": bool(r[3]),
                   "input": r[4], "overlay_pkg": r[5], "ubuntu_src": r[6],
                   "derived": bool(r[6]) and r[1] != r[6], "older": bool(r[7])} for r in rows]))'
