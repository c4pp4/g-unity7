#!/bin/bash
## Print the packages as JSON: name, source package, group, local and source
##  archive (SOURCE_ARCHIVE). With --input <overlay>, also print the input hash.

set -euo pipefail
source "$(dirname "$0")"/lib.sh

overlay=
[[ ${1:-} == --input ]] && overlay=$(realpath "$2")

{
	for pkg in $(list_packages); do
		load_package "${pkg}"
		input=
		[[ -n ${overlay} ]] && input=$(input_hash "${overlay}")
		printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${pkg}" "${SOURCE_NAME}" "${GROUP:-}" "${LOCAL:-}" "${input}" \
			"${SOURCE_ARCHIVE:-}"
	done
} | python3 -I -c '
import json, sys
rows = [line.rstrip("\n").split("\t") for line in sys.stdin]
print(json.dumps([{"name": r[0], "source": r[1], "group": r[2], "local": bool(r[3]),
                   "input": r[4], "source_archive": r[5]} for r in rows]))'
