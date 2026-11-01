#!/bin/bash
## Build the G Unity⁷ source package of packages/<package> for one series:
##  the newest Ubuntu source with the overlay patches, the edits of the ebuild
##  as a patch and the debian/ changes, then check it and write a review.
##
## Usage: build-source.sh [--series <series>] [--force] <package>
##
##  --force  build even if the staging PPA has the same fingerprint
##
## Environment:
##  OVERLAY_DIR  gentoo-unity7 checkout (default: ../gentoo-unity7)
##  BUILD_DIR    output directory (default: build/)
##
## Output in BUILD_DIR/<series>/<package>/:
##  out/        the signed-to-be source package (.dsc, .changes, tarballs)
##  review/     debdiff.diff, code.diff, summary.md
##  result.env  STATUS (built|uptodate), VERSION, FINGERPRINT, NEEDS_REVIEW, ...

set -euo pipefail
source "$(dirname "$0")"/lib.sh

series=${SERIES[0]}
force=
while [[ $# -gt 0 ]]; do
	case $1 in
		--series) series=$2; shift 2 ;;
		--force) force=1; shift ;;
		-h|--help) sed -n '2,/^$/s/^## \{0,1\}//p' "$0"; exit 0 ;;
		-*) die "Unknown option: $1" ;;
		*) break ;;
	esac
done
[[ $# -eq 1 ]] || die "Usage: $0 [--series <series>] [--force] <package>"
pkg=$1
series_version=${SERIES_VERSION[${series}]:-}
[[ -n ${series_version} ]] || die "Unknown series ${series}, see config.sh."
[[ -n ${DEBEMAIL} ]] || die "DEBEMAIL is not set."

OVERLAY_DIR=$(realpath "${OVERLAY_DIR:-${REPO_ROOT}/../gentoo-unity7}")
grep -Fqsx "gentoo-unity7" "${OVERLAY_DIR}"/profiles/repo_name \
	|| die "gentoo-unity7 overlay not found in ${OVERLAY_DIR}, set OVERLAY_DIR."

load_package "${pkg}"

## For debian_edit and src_edit, as in the ebuild.
FILESDIR="${OVERLAY_DIR}/${OVERLAY_PKG:-}/files"
BRANDING_DIR="${REPO_ROOT}/branding"

export QUILT_PATCHES=debian/patches
export QUILT_PC=.pc
export QUILT_REFRESH_ARGS="-p ab --no-timestamps --no-index"
export QUILT_NO_DIFF_TIMESTAMPS=1
export DEBFULLNAME DEBEMAIL

base_dir="${BUILD_DIR:-${REPO_ROOT}/build}/${series}/${pkg}"
work="${base_dir}/work"
rm -rf "${base_dir}"
mkdir -p "${work}" "${base_dir}"/out "${base_dir}"/review

overlay_commit=$(git_commit "${OVERLAY_DIR}" ${OVERLAY_PKG:+"${OVERLAY_PKG}"})
repo_commit=$(git_commit "${REPO_ROOT}" "${PKG_DIR#"${REPO_ROOT}"/}")
[[ -n ${OVERLAY_PKG:-} && ${overlay_commit} == *-dirty ]] && ewarn "${OVERLAY_PKG} has uncommitted changes in the overlay."
[[ -n ${OVERLAY_REF[${series}]:-} ]] && einfo "Series ${series} is built from overlay ${OVERLAY_REF[${series}]}."
tree="${work}/tree"

if [[ -n ${LOCAL:-} ]]; then
	## 1.-2. Own package: the source is local/<package> without package.sh,
	##  its base version is the one of its debian/changelog.
	mkdir -p "${tree}" "${work}"/debian.orig
	(cd "${PKG_DIR}" && tar --exclude=./package.sh -cf - .) | (cd "${tree}" && tar -xf -)
	sed -i "s/@MAINTAINER@/${DEBFULLNAME} <${DEBEMAIL}>/" "${tree}"/debian/control "${tree}"/debian/changelog
	ubuntu_version=$(dpkg-parsechangelog -l "${tree}"/debian/changelog -S Version)
	orig_dsc=
	einfo "${SOURCE_NAME} ${ubuntu_version} (local/${pkg})"
else
	## 1. Newest Ubuntu version.
	read -r ubuntu_version ubuntu_pocket < <(python3 -I "${REPO_ROOT}"/scripts/lp.py \
		ubuntu-version "${UBUNTU_SRC}" --series "${series}")
	einfo "${UBUNTU_SRC} ${ubuntu_version} (${series} ${ubuntu_pocket})"

	## 2. Download and unpack without patches.
	(cd "${work}" && pull-lp-source --download-only "${UBUNTU_SRC}" "${ubuntu_version}" >&2) \
		|| die "Download of ${UBUNTU_SRC} ${ubuntu_version} failed."
	orig_dsc="${work}/${UBUNTU_SRC}_${ubuntu_version#*:}.dsc"
	dpkg-source --no-check -x --skip-patches "${orig_dsc}" "${tree}" >/dev/null \
		|| die "Unpacking ${orig_dsc##*/} failed."
	cp -a "${tree}"/debian "${work}"/debian.orig

	## Derived source package (SOURCE_NAME): the Ubuntu source under another
	##  name, its orig tarball copied under that name.
	if [[ ${SOURCE_NAME} != "${UBUNTU_SRC}" ]]; then
		upstream=${ubuntu_version#*:}
		upstream=${upstream%-*}
		sed -i "s/^Source: .*/Source: ${SOURCE_NAME}/" "${tree}"/debian/control
		grep -qx "Source: ${SOURCE_NAME}" "${tree}"/debian/control || die "Renaming the source failed."
		for f in "${work}/${UBUNTU_SRC}_${upstream}".orig*.tar.*; do
			[[ -f ${f} ]] && cp "${f}" "${work}/${SOURCE_NAME}_${f#"${work}/${UBUNTU_SRC}_"}"
		done
		einfo "Derived source ${SOURCE_NAME} from ${UBUNTU_SRC}."
	fi
fi

format=$(cat "${tree}"/debian/source/format 2>/dev/null || echo "1.0")
if [[ -z ${PATCH_MODE:-} ]]; then
	case ${format} in
		"3.0 (quilt)") PATCH_MODE=quilt ;;
		"1.0")
			PATCH_MODE=direct
			if has_patches "${tree}"; then
				grep -q quilt "${tree}"/debian/rules "${tree}"/debian/control \
					|| die "Format 1.0 with debian/patches/series not applied by quilt, set PATCH_MODE."
				PATCH_MODE=quilt
			fi
			;;
		*) PATCH_MODE=direct ;;
	esac
fi
einfo "Source format ${format}, patch mode ${PATCH_MODE}."

cd "${tree}"

## 3. debian/ changes, before the Ubuntu patchset is applied, as they may
##  change it (debian/patches/series).
if [[ -z ${LOCAL:-} && -d ${PKG_DIR}/debian ]]; then
	cp -a "${PKG_DIR}"/debian/. debian/
fi
if declare -F local_prepare >/dev/null; then
	local_prepare || die "local_prepare failed."
fi
if declare -F debian_edit >/dev/null; then
	debian_edit || die "debian_edit failed."
fi

## Apply the Ubuntu patchset first, the overlay patches go on top of it.
if [[ ${PATCH_MODE} == quilt ]] && has_patches .; then
	quilt push -a -q --fuzz=0 >/dev/null || die "The Ubuntu patchset does not apply."
fi

## Patch lines of the changelog ("name hash"), the fingerprint is made of them.
patch_lines=()
patch_names=()
dep3_dir="${work}/patches"
mkdir -p "${dep3_dir}"

## Apply a DEP-3 patch ($1) named $2.
add_patch() {
	local file=$1 name=$2
	if [[ ${PATCH_MODE} == quilt ]]; then
		quilt import -P "g-unity7/${name}" "${file}" >/dev/null || die "quilt import of ${name} failed."
		quilt push -q --fuzz=0 >/dev/null || die "${name} does not apply (see quilt push --fuzz=0)."
	else
		patch -p1 -s --fuzz=0 --no-backup-if-mismatch -i "${file}" || die "${name} does not apply."
	fi
}

## 4. Overlay patches.
for name in "${PATCHES[@]}"; do
	if [[ -f ${PKG_DIR}/patches/${name} ]]; then
		src="${PKG_DIR}/patches/${name}"
		origin="${G_UNITY7_URL}/blob/${repo_commit%-dirty}/packages/${pkg}/patches/${name}"
	else
		src="${OVERLAY_DIR}/${OVERLAY_PKG}/files/${name}"
		origin="${OVERLAY_URL}/blob/${overlay_commit%-dirty}/${OVERLAY_PKG}/files/${name}"
	fi
	[[ -f ${src} ]] || die "Patch ${name} not found (${src})."
	python3 -I "${REPO_ROOT}"/scripts/dep3.py "${src}" --name "${name}" --origin "${origin}" \
		--author "${DEBFULLNAME}" --email "${DEBEMAIL}" > "${dep3_dir}/${name}"
	add_patch "${dep3_dir}/${name}" "${name}"
	patch_lines+=( "${name} $(short_hash < "${src}")" )
	patch_names+=( "${name}" )
	einfo "Applied ${name}"
done

## 5. Edits of the ebuild (src_edit) as one more patch.
if declare -F src_edit >/dev/null; then
	git_tree=( git -c safe.directory='*' -c core.excludesFile=/dev/null -c core.attributesFile=/dev/null
		-c user.name=g-unity7 -c user.email=g-unity7@localhost )
	"${git_tree[@]}" init -q
	"${git_tree[@]}" add -A -f .
	"${git_tree[@]}" commit -q -m snapshot
	src_edit || die "src_edit failed."
	"${git_tree[@]}" add -A -f .
	edits="${work}/ebuild-edits.diff"
	"${git_tree[@]}" diff --cached --no-color --no-renames -p > "${edits}"
	if [[ ! -s ${edits} ]]; then
		die "src_edit changed nothing."
	fi
	if [[ ${PATCH_MODE} == quilt ]]; then
		"${git_tree[@]}" diff --cached --numstat | grep -q '^-' \
			&& die "src_edit changed a binary file, which quilt can't patch."
		"${git_tree[@]}" reset -q --hard
	fi
	rm -rf .git
	{
		echo "Description: Edits of the gentoo-unity7 ebuild"
		echo " Changes made by sed and other commands in src_prepare of"
		echo " ${OVERLAY_PKG}, ported in packages/${pkg}/package.sh."
		echo "Author: ${DEBFULLNAME} <${DEBEMAIL}>"
		echo "Origin: vendor, ${G_UNITY7_URL}/blob/${repo_commit%-dirty}/packages/${pkg}/package.sh"
		echo "Forwarded: not-needed"
		echo "---"
		cat "${edits}"
	} > "${dep3_dir}"/ebuild-edits.patch
	[[ ${PATCH_MODE} == quilt ]] && add_patch "${dep3_dir}"/ebuild-edits.patch ebuild-edits.patch
	patch_lines+=( "ebuild-edits.patch $(changed_lines < "${edits}" | short_hash)" )
	patch_names+=( ebuild-edits.patch )
	einfo "Applied ebuild-edits.patch"
fi

## 6. Leave the patches unapplied, dpkg-source and debian/rules apply them.
if [[ ${PATCH_MODE} == quilt ]]; then
	quilt pop -a -q >/dev/null 2>&1 || true
	rm -rf .pc
fi

## Hash of the debian/ changes, without the changelog and the overlay patches
##  (they have their own patch lines) and their lines in the series file. The
##  patches of Ubuntu and the series lines changed by debian_edit count
##  (pre_populator.patch of zeitgeist, the Debian PCRE2 patch of nux).
debian_diff="${work}/debian.diff"
(cd "${work}" && diff -Nura -x changelog debian.orig tree/debian || true) \
	| awk '/^diff / { skip = ($NF ~ /\/debian\/patches\/g-unity7\//); series = ($NF ~ /\/debian\/patches\/series$/) }
		!skip && !(series && /^\+g-unity7\//)' > "${debian_diff}"
if [[ -n ${LOCAL:-} ]]; then
	## The whole source of an own package.
	patch_lines+=( "source $(find . -type f ! -path ./debian/changelog -print0 | sort -z \
		| xargs -0 sha256sum | short_hash)" )
elif [[ -s ${debian_diff} ]]; then
	patch_lines+=( "debian $(changed_lines < "${debian_diff}" | short_hash)" )
fi
[[ ${#patch_lines[@]} -gt 0 ]] || die "Nothing is changed in ${pkg}."

input=$(input_hash "${OVERLAY_DIR}")
fingerprint=$( { echo "format ${FORMAT_VERSION}"; printf '%s\n' "${patch_lines[@]}"; } | sha256sum | cut -c1-32)

## 8. Version: <ubuntu version>+gu7.<N>~<series version>.
staging_json=$(python3 -I "${REPO_ROOT}"/scripts/lp.py ppa-latest "${SOURCE_NAME}" \
	--ppa "${PPA_STAGING}" --series "${series}")
main_json=$(python3 -I "${REPO_ROOT}"/scripts/lp.py ppa-latest "${SOURCE_NAME}" \
	--ppa "${PPA_MAIN}" --series "${series}")
json_get() {
	python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); print(d.get(sys.argv[2], ""))' "$1" "$2"
}
staging_version=$(json_get "${staging_json}" version)
staging_fingerprint=$(json_get "${staging_json}" fingerprint)

suffix_re="^(.*)\+${VERSION_TAG}\.([0-9]+)~[0-9.]+$"
n=1
needs_review=1
if [[ ${staging_version} =~ ${suffix_re} ]]; then
	staging_base=${BASH_REMATCH[1]}
	staging_n=${BASH_REMATCH[2]}
	[[ ${staging_fingerprint} == "${fingerprint}" ]] && needs_review=
	if [[ ${staging_base} == "${ubuntu_version}" ]]; then
		if [[ -z ${needs_review} && -z ${force} ]]; then
			einfo "${SOURCE_NAME} ${staging_version} in ${PPA_STAGING} is up to date."
			cat > "${base_dir}"/result.env <<-EOF
				STATUS=uptodate
				SOURCE=${SOURCE_NAME}
				VERSION=${staging_version}
				FINGERPRINT=${fingerprint}
				INPUT=${input}
			EOF
			exit 0
		fi
		n=$(( staging_n + 1 ))
	fi
fi
version="${ubuntu_version}+${VERSION_TAG}.${n}~${series_version}"

## "Changes since" against the version users have in the main PPA.
changes_since=()
main_version=$(json_get "${main_json}" version)
if [[ -n ${main_version} ]]; then
	mapfile -t changes_since < <(python3 -I - "${main_json}" "${patch_lines[@]}" <<-'EOF'
		import json, sys
		old = json.loads(sys.argv[1]).get("patches", {})
		new = dict(line.split(" ", 1) for line in sys.argv[2:])
		for name in new:
		    if name not in old:
		        print(f"added: {name}")
		    elif old[name] != new[name]:
		        print(f"updated: {name}")
		for name in old:
		    if name not in new:
		        print(f"removed: {name}")
	EOF
	)
	if [[ ${#changes_since[@]} -eq 0 ]]; then
		if [[ ${main_version} =~ ${suffix_re} && ${BASH_REMATCH[1]} != "${ubuntu_version}" ]]; then
			changes_since=( "rebased on ${ubuntu_version}" )
		else
			changes_since=( "No-change rebuild" )
		fi
	fi
fi

entry="${work}/changelog.entry"
{
	echo "${SOURCE_NAME} (${version}) ${series}; urgency=medium"
	echo
	if [[ -n ${OVERLAY_PKG:-} ]]; then
		echo "  * G Unity⁷ patches from c4pp4/gentoo-unity7@${overlay_commit:0:12}."
	else
		echo "  * G Unity⁷ package from c4pp4/g-unity7@${repo_commit:0:12}."
	fi
	if [[ ${#changes_since[@]} -gt 0 ]]; then
		echo "  * Changes since ${main_version} (ppa:${PPA_MAIN}):"
		printf '    - %s\n' "${changes_since[@]}"
	fi
	echo "  * Patches:"
	for line in "${patch_lines[@]}"; do
		echo "    - ${line% *} [${line##* }]"
	done
	echo "  * G-Unity7-Fingerprint: ${fingerprint}"
	echo "  * G-Unity7-Input: ${input}"
	echo
	echo " -- ${DEBFULLNAME} <${DEBEMAIL}>  $(date -R)"
	echo
} > "${entry}"
cat "${entry}" debian/changelog > "${work}"/changelog.new
mv "${work}"/changelog.new debian/changelog
dpkg-parsechangelog -S Version >/dev/null || die "Generated changelog is not valid."
einfo "Version ${version}"

## 9. Source package.
dpkg-buildpackage -S -sa -d -nc -us -uc >"${work}"/dpkg-buildpackage.log 2>&1 \
	|| { tail -n 30 "${work}"/dpkg-buildpackage.log >&2; die "dpkg-buildpackage failed."; }
changes="${work}/${SOURCE_NAME}_${version#*:}_source.changes"
dsc="${work}/${SOURCE_NAME}_${version#*:}.dsc"
dcmd cp "${changes}" "${base_dir}"/out/
cp "${work}"/dpkg-buildpackage.log "${base_dir}"/out/

## 10. Check that every patch applies without fuzz to the unpacked package.
check="${work}/check"
dpkg-source --no-check -x --skip-patches "${dsc}" "${check}" >/dev/null || die "Unpacking ${dsc##*/} failed."
if [[ ${PATCH_MODE} == quilt ]]; then
	(cd "${check}" && quilt push -a -q --fuzz=0 >/dev/null) || die "Patches of ${dsc##*/} do not apply without fuzz."
fi
einfo "Patches apply without fuzz."

## 11. Review.
"${REPO_ROOT}"/scripts/make-review.sh \
	--orig "${orig_dsc}" --new "${dsc}" --checked "${check}" --work "${work}" \
	--entry "${entry}" --mode "${PATCH_MODE}" --out "${base_dir}"/review \
	--package "${pkg}" --overlay-commit "${overlay_commit}" -- "${patch_names[@]}"

printf '%s\n' "${patch_lines[@]}" > "${base_dir}"/patches.txt
cat > "${base_dir}"/result.env <<-EOF
	STATUS=built
	SOURCE=${SOURCE_NAME}
	VERSION=${version}
	FINGERPRINT=${fingerprint}
	INPUT=${input}
	NEEDS_REVIEW=${needs_review}
	GROUP=${GROUP:-}
	CHANGES=out/${changes##*/}
	STAGING_VERSION=${staging_version}
	MAIN_VERSION=${main_version}
EOF
einfo "Done: ${base_dir}/out/${changes##*/}$([[ -n ${needs_review} ]] && echo ", review needed")"
