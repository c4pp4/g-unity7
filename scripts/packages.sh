#!/bin/bash
## Print the packages as JSON: name, source package, group, local, and with
##  --input <overlay> also the input hash and the Ubuntu or local base version.

set -euo pipefail
source "$(dirname "$0")"/lib.sh

overlay=
[[ ${1:-} == --input ]] && overlay=$(realpath "$2")

{
	for pkg in $(list_packages); do
		load_package "${pkg}"
		input=
		[[ -n ${overlay} ]] && input=$(input_hash "${overlay}")
		printf '%s\t%s\t%s\t%s\t%s\n' "${pkg}" "${SOURCE_NAME}" "${GROUP:-}" "${LOCAL:-}" "${input}"
	done
} | python3 -I -c '
import json, sys
rows = [line.rstrip("\n").split("\t") for line in sys.stdin]
print(json.dumps([{"name": r[0], "source": r[1], "group": r[2], "local": bool(r[3]),
                   "input": r[4]} for r in rows]))'
