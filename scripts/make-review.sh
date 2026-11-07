#!/bin/bash
## Write the review of a source package built by build-source.sh:
##  debdiff.diff  the whole difference between the source package and Ubuntu
##  code.diff     the code changes with all patches applied
##  summary.md    patches, ebuild edits, debian/ changes and the changelog entry

set -euo pipefail
source "$(dirname "$0")"/lib.sh

while [[ $# -gt 0 ]]; do
	case $1 in
		--orig) orig_dsc=$2; shift 2 ;;
		--new) new_dsc=$2; shift 2 ;;
		--checked) checked=$2; shift 2 ;;
		--work) work=$2; shift 2 ;;
		--entry) entry=$2; shift 2 ;;
		--mode) mode=$2; shift 2 ;;
		--out) out=$2; shift 2 ;;
		--package) pkg=$2; shift 2 ;;
		--overlay-pkg) overlay_pkg=$2; shift 2 ;;
		--overlay-commit) overlay_commit=$2; shift 2 ;;
		--) shift; break ;;
		*) die "Unknown option: $1" ;;
	esac
done
patch_names=( "$@" )
load_package "${pkg}"
## The ehooks directory that build-source.sh picked for the base version.
[[ -n ${overlay_pkg:-} ]] && OVERLAY_PKG=${overlay_pkg}

## Compare our source with the Ubuntu source with its own patches applied.
##  An own package (no --orig) is compared with nothing, including debian/.
orig_tree="${work}/orig-applied"
exclude=( -x .pc )
if [[ -n ${orig_dsc} ]]; then
	debdiff "${orig_dsc}" "${new_dsc}" > "${out}"/debdiff.diff 2>/dev/null || true
	dpkg-source --no-check -x --skip-patches "${orig_dsc}" "${orig_tree}" >/dev/null
	if [[ ${mode} == quilt ]] && has_patches "${orig_tree}"; then
		(cd "${orig_tree}" && QUILT_PATCHES=debian/patches quilt push -a -q >/dev/null)
	fi
	exclude+=( -x debian )
else
	mkdir -p "${orig_tree}"
	: > "${out}"/debdiff.diff
fi
(cd "${work}" && diff -Nur "${exclude[@]}" "${orig_tree##*/}" "${checked##*/}" > "${out}"/code.diff || true)

description() {
	sed -n 's/^Description: //p;T;q' "$1"
}

{
	echo "# ${SOURCE_NAME} $(dpkg-parsechangelog -l "${checked}"/debian/changelog -S Version)"
	echo
	if [[ -n ${orig_dsc} ]]; then
		if [[ -n ${DEBIAN_SUITE:-} ]]; then
			echo "- Debian source: \`${orig_dsc##*/}\` (${DEBIAN_SUITE})"
		else
			echo "- Ubuntu source: \`${orig_dsc##*/}\`"
		fi
	else
		echo "- Own package: \`local/${pkg}\` (the whole source is in code.diff)"
	fi
	[[ -n ${OVERLAY_PKG:-} ]] && echo "- Overlay: \`${OVERLAY_PKG}\` at \`${overlay_commit}\`"
	echo "- Patch mode: ${mode}"
	echo "- Code: $(diffstat -s "${out}"/code.diff 2>/dev/null || echo "no changes")"
	echo
	echo "## Patches"
	echo
	echo "| Patch | Source | Description |"
	echo "|---|---|---|"
	for name in "${patch_names[@]}"; do
		if [[ ${name} == ebuild-edits.patch ]]; then
			where="packages/${pkg}/package.sh (src_edit)"
		elif [[ -f ${PKG_DIR}/patches/${name} ]]; then
			where="packages/${pkg}/patches/${name}"
		else
			where="${OVERLAY_PKG}/files/${name}"
		fi
		echo "| \`${name}\` | \`${where}\` | $(description "${work}/patches/${name}" | sed 's/|/\\|/g') |"
	done
	echo
	if [[ -s ${work}/ebuild-edits.diff ]]; then
		echo "## Ebuild edits"
		echo
		echo '```diff'
		cat "${work}"/ebuild-edits.diff
		echo '```'
		echo
	fi
	echo "## debian/ changes"
	echo
	if [[ -s ${work}/debian.diff ]]; then
		echo "Without \`debian/patches/\` and \`debian/changelog\`:"
		echo
		echo '```diff'
		cat "${work}"/debian.diff
		echo '```'
	else
		echo "None, apart from the patches and the changelog."
	fi
	echo
	echo "## Changelog entry"
	echo
	echo '```'
	cat "${entry}"
	echo '```'
} > "${out}"/summary.md
