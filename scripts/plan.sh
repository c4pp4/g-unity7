#!/bin/bash
## Print the packages to build as a JSON list: those whose Ubuntu version or
##  input hash differs from their newest version in the staging PPA. A package
##  waiting for review, or rejected, with the same Ubuntu version and input
##  hash is not built again.
##
## Usage: plan.sh [--series <series>] [--force] [--state <file>] [<package>...]
##
##  --force  list the given packages (all without them) even if unchanged
##  --state  state JSON of the approval issue (see approve.py)

set -euo pipefail
source "$(dirname "$0")"/lib.sh

series=${SERIES[0]}
force=
state=
while [[ $# -gt 0 ]]; do
	case $1 in
		--series) series=$2; shift 2 ;;
		--force) force=1; shift ;;
		--state) state=$2; shift 2 ;;
		-*) die "Unknown option: $1" ;;
		*) break ;;
	esac
done
OVERLAY_DIR=$(realpath "${OVERLAY_DIR:-${REPO_ROOT}/../gentoo-unity7}")

packages=( "$@" )
[[ ${#packages[@]} -gt 0 ]] || mapfile -t packages < <(list_packages)

## Print field $2 of JSON $1, or of the entry $3 of the state section $2.
json_get() {
	python3 -I -c '
import json, sys
d = json.loads(sys.argv[1] or "{}")
for key in sys.argv[2:]:
    d = d.get(key, {}) if isinstance(d, dict) else {}
print(d if isinstance(d, str) else "")' "$@"
}

state_json=
[[ -n ${state} && -s ${state} ]] && state_json=$(cat "${state}")

selected=()
for pkg in "${packages[@]}"; do
	load_package "${pkg}"
	if [[ -n ${force} ]]; then
		selected+=( "${pkg}" )
		continue
	fi
	if [[ -n ${LOCAL:-} ]]; then
		base=$(sed -n '1s/^[^ ]* (\([^)]*\)).*/\1/p' "${PKG_DIR}"/debian/changelog)
	else
		read -r base _ < <(python3 -I "${REPO_ROOT}"/scripts/lp.py ubuntu-version "${UBUNTU_SRC}" --series "${UBUNTU_SERIES:-${series}}")
	fi
	input=$(input_hash "${OVERLAY_DIR}")
	staging=$(python3 -I "${REPO_ROOT}"/scripts/lp.py ppa-latest "${SOURCE_NAME}" \
		--ppa "${PPA_STAGING}" --series "${series}" 2>/dev/null)
	staging_version=$(json_get "${staging}" version)
	staging_base=${staging_version%+"${VERSION_TAG}".*}

	if [[ -n ${staging_version} && ${staging_base} == "${base}" && $(json_get "${staging}" input) == "${input}" ]]; then
		einfo "${pkg}: up to date (${staging_version})"
		continue
	fi
	for section in review rejected; do
		if [[ $(json_get "${state_json}" "${section}" "${pkg}" base) == "${base}" \
			&& $(json_get "${state_json}" "${section}" "${pkg}" input) == "${input}" ]]; then
			einfo "${pkg}: unchanged since it was put for review (${section})"
			continue 2
		fi
	done
	einfo "${pkg}: build (Ubuntu ${base}, staging ${staging_version:-none})"
	selected+=( "${pkg}" )
done

python3 -I -c 'import json, sys; print(json.dumps(sys.argv[1:]))' "${selected[@]}"
