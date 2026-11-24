#!/bin/bash
## Print the packages to build as a JSON list: those whose Ubuntu version or
##  input hash differs from their latest version in the staging PPA. A package
##  that waits for review or was rejected with the same Ubuntu version and
##  input hash is not built again, nor one whose staging version the approval
##  issue knows with the same input hash (the last build found it up to date,
##  or it was uploaded from this input). The staging PPA is listed once, and
##  the changelog of a version is read only when the issue does not know its
##  input hash.
##
## Usage: plan.sh [--series <series>] [--force] [--state <file>] [--errors <file>]
##          [<package>...]
##
##  --force   list the given packages (or all packages) even if unchanged
##  --state   state JSON of the approval issue (see approve.py)
##  --errors  write the checked packages (checked) and those that could not be
##            checked, such as after a Launchpad error, with the last line of
##            the error (errors) as JSON. A package that cannot be checked does
##            not stop the others; plan.sh fails only when no package could be
##            checked.

set -euo pipefail
source "$(dirname "$0")"/lib.sh

series=${SERIES[0]}
force=
state=
errors_file=
while [[ $# -gt 0 ]]; do
	case $1 in
		--series) series=$2; shift 2 ;;
		--force) force=1; shift ;;
		--state) state=$2; shift 2 ;;
		--errors) errors_file=$2; shift 2 ;;
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

## One listing of the staging PPA instead of a query for each package
listing=
[[ -n ${force} ]] || listing=$(python3 -I "${REPO_ROOT}"/scripts/lp.py ppa-sources \
	--ppa "${PPA_STAGING}" --series "${series}")

## Print "build" or "skip" for package $1. The reasons go to stderr. It runs in
##  a subshell with errexit, so that an error stops only this package.
decide() {
	local pkg=$1 base mark= input staging_version staging_base staging section
	load_package "${pkg}"
	## HOLD in package.sh keeps the latest version in the staging PPA, even with
	##  --force, for example until an overlay patch applies to a new version.
	if [[ -n ${HOLD:-} ]]; then
		einfo "${pkg}: held (${HOLD})"
		echo skip
		return
	fi
	if [[ -n ${force} ]]; then
		echo build
		return
	fi
	if [[ -n ${LOCAL:-} ]]; then
		base=$(sed -n '1s/^[^ ]* (\([^)]*\)).*/\1/p' "${PKG_DIR}"/debian/changelog)
	elif [[ -n ${DEBIAN_SUITE:-} ]]; then
		read -r base _ < <(python3 -I "${REPO_ROOT}"/scripts/lp.py debian-version "${UBUNTU_SRC}" --suite "${DEBIAN_SUITE}")
	else
		read -r base _ < <(python3 -I "${REPO_ROOT}"/scripts/lp.py ubuntu-version "${UBUNTU_SRC}" --series "${UBUNTU_SERIES:-${series}}")
	fi
	## The mark between the base and +gu7 (see version_mark in build-source.sh);
	##  a version from before the mark counts until it is deleted
	[[ -n ${LOCAL:-} || -n ${DEBIAN_SUITE:-} || -n ${UBUNTU_SERIES:-} ]] || mark=$(version_mark "${base}")
	input=$(input_hash "${OVERLAY_DIR}")
	staging_version=$(json_get "${listing}" "${SOURCE_NAME}")
	staging_base=${staging_version%+"${VERSION_TAG}".*}

	if [[ -n ${staging_version} && ( ${staging_base} == "${base}${mark}" || ${staging_base} == "${base}" ) ]]; then
		## The approval issue knows the input of the staging version: the last
		##  build found it up to date with this input, or it was uploaded from it
		if [[ $(json_get "${state_json}" uptodate "${pkg}" version) == "${staging_version}" \
			&& $(json_get "${state_json}" uptodate "${pkg}" input) == "${input}" ]]; then
			einfo "${pkg}: up to date (${staging_version}, the same input in the approval issue)"
			echo skip
			return
		fi
		staging=$(python3 -I "${REPO_ROOT}"/scripts/lp.py ppa-latest "${SOURCE_NAME}" \
			--ppa "${PPA_STAGING}" --series "${series}")
		if [[ $(json_get "${staging}" input) == "${input}" ]]; then
			einfo "${pkg}: up to date (${staging_version})"
			echo skip
			return
		fi
	fi
	for section in review rejected; do
		if [[ $(json_get "${state_json}" "${section}" "${pkg}" base) == "${base}" \
			&& $(json_get "${state_json}" "${section}" "${pkg}" input) == "${input}" ]]; then
			einfo "${pkg}: unchanged since it was queued (${section})"
			echo skip
			return
		fi
	done
	einfo "${pkg}: build (base ${base}, staging ${staging_version:-none})"
	echo build
}

selected=()
checked=()
errors=()
tmp=$(mktemp -d)
trap 'rm -rf -- "${tmp}"' EXIT
for pkg in "${packages[@]}"; do
	## errexit stays on in the subshell, which is not a condition
	set +e
	( set -e; decide "${pkg}" ) > "${tmp}"/out 2> "${tmp}"/err
	status=$?
	set -e
	cat "${tmp}"/err >&2
	if [[ ${status} -ne 0 ]]; then
		message=$(sed -e 's/\x1b\[[0-9;]*m//g' -e '/^[[:space:]]*$/d' "${tmp}"/err | tail -n 1 | cut -c1-300)
		message=${message:-exit status ${status}}
		ewarn "${pkg}: cannot be checked: ${message}"
		errors+=( "${pkg}" "${message}" )
		continue
	fi
	checked+=( "${pkg}" )
	[[ $(< "${tmp}"/out) != build ]] || selected+=( "${pkg}" )
done

if [[ -n ${errors_file} ]]; then
	python3 -I - "${errors_file}" "${#checked[@]}" "${checked[@]}" "${errors[@]}" <<-'EOF'
		import json, sys
		path, count = sys.argv[1], int(sys.argv[2])
		checked, rest = sys.argv[3:3 + count], sys.argv[3 + count:]
		with open(path, "w") as f:
		    json.dump({"checked": checked, "errors": dict(zip(rest[0::2], rest[1::2]))}, f, ensure_ascii=False)
	EOF
fi
[[ ${#checked[@]} -gt 0 || ${#packages[@]} -eq 0 ]] || die "No package could be checked."

python3 -I -c 'import json, sys; print(json.dumps(sys.argv[1:]))' "${selected[@]}"
