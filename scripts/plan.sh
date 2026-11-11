#!/bin/bash
## Print the packages to build as a JSON list: those whose Ubuntu version or
##  input hash differs from their latest version in the staging PPA. A package
##  that waits for review or was rejected with the same Ubuntu version and
##  input hash is not built again, nor one whose last build found the staging
##  version up to date with the same input hash.
##
## Usage: plan.sh [--series <series>] [--force] [--state <file>] [<package>...]
##
##  --force  list the given packages (or all packages) even if unchanged
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

## Print field $2 of JSON $1, or of entry $3 in state section $2.
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
	## HOLD in package.sh keeps the latest version in the staging PPA, even with
	##  --force, for example until an overlay patch applies to a new version.
	if [[ -n ${HOLD:-} ]]; then
		einfo "${pkg}: held (${HOLD})"
		continue
	fi
	if [[ -n ${force} ]]; then
		selected+=( "${pkg}" )
		continue
	fi
	if [[ -n ${LOCAL:-} ]]; then
		base=$(sed -n '1s/^[^ ]* (\([^)]*\)).*/\1/p' "${PKG_DIR}"/debian/changelog)
	elif [[ -n ${DEBIAN_SUITE:-} ]]; then
		read -r base _ < <(python3 -I "${REPO_ROOT}"/scripts/lp.py debian-version "${UBUNTU_SRC}" --suite "${DEBIAN_SUITE}")
	else
		read -r base _ < <(python3 -I "${REPO_ROOT}"/scripts/lp.py ubuntu-version "${UBUNTU_SRC}" --series "${UBUNTU_SERIES:-${series}}")
	fi
	input=$(input_hash "${OVERLAY_DIR}")
	staging=$(python3 -I "${REPO_ROOT}"/scripts/lp.py ppa-latest "${SOURCE_NAME}" \
		--ppa "${PPA_STAGING}" --series "${series}")
	staging_version=$(json_get "${staging}" version)
	staging_base=${staging_version%+"${VERSION_TAG}".*}

	if [[ -n ${staging_version} && ${staging_base} == "${base}" && $(json_get "${staging}" input) == "${input}" ]]; then
		einfo "${pkg}: up to date (${staging_version})"
		continue
	fi
	for section in review rejected; do
		if [[ $(json_get "${state_json}" "${section}" "${pkg}" base) == "${base}" \
			&& $(json_get "${state_json}" "${section}" "${pkg}" input) == "${input}" ]]; then
			einfo "${pkg}: unchanged since it was queued (${section})"
			continue 2
		fi
	done
	## The last build found the staging version up to date with this input:
	##  the same fingerprint, only the input hash changed (approve.py add-review).
	if [[ -n ${staging_version} && $(json_get "${state_json}" uptodate "${pkg}" version) == "${staging_version}" \
		&& $(json_get "${state_json}" uptodate "${pkg}" input) == "${input}" ]]; then
		einfo "${pkg}: up to date (${staging_version}, the same fingerprint with this input)"
		continue
	fi
	einfo "${pkg}: build (base ${base}, staging ${staging_version:-none})"
	selected+=( "${pkg}" )
done

python3 -I -c 'import json, sys; print(json.dumps(sys.argv[1:]))' "${selected[@]}"
