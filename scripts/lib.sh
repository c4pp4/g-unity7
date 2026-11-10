# shellcheck shell=bash
# Common functions for the G Unity⁷ scripts.

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

color_green=$(tput bold 2>/dev/null; tput setaf 2 2>/dev/null) || true
color_yellow=$(tput bold 2>/dev/null; tput setaf 3 2>/dev/null) || true
color_red=$(tput bold 2>/dev/null; tput setaf 1 2>/dev/null) || true
color_norm=$(tput sgr0 2>/dev/null) || true

einfo() {
	echo " ${color_green}*${color_norm} $*" >&2
}

ewarn() {
	echo " ${color_yellow}*${color_norm} $*" >&2
}

die() {
	echo " ${color_red}*${color_norm} $*" >&2
	exit 1
}

source "${REPO_ROOT}"/config.sh

## Print the first 12 hex digits of the SHA-256 hash of stdin.
short_hash() {
	sha256sum | cut -c1-12
}

## Succeed if the source tree $1 has a patch in debian/patches/series. A series
##  file with only an empty line or comments has none, and quilt fails on it.
has_patches() {
	grep -q '^[^#[:space:]]' "$1"/debian/patches/series 2>/dev/null
}

## For src_edit: merge the po files from tarball $1 (po/*.po) into the po files
##  of the source in the current directory, like "msgcat --use-first" in the
##  ehooks, but only append the messages that the source lacks, so that the
##  files are not reformatted.
merge_translations() {
	local tmp po target body
	tmp=$(mktemp -d) || return 1
	tar -xf "$1" -C "${tmp}" || return 1
	for po in "${tmp}"/po/*.po; do
		target=po/${po##*/}
		[[ -f ${target} ]] || continue
		rm -f "${tmp}"/unique.po "${tmp}"/add.po
		msgattrib --no-obsolete -o "${tmp}"/new.po "${po}" || return 1
		# Every message in the source counts as defined, including fuzzy and #
		#  untranslated ones, which msgcat ignores, and obsolete ones, because #
		#  msgfmt from gettext 1.0 rejects an active duplicate of them #
		msgattrib --clear-obsolete --clear-fuzzy -o "${tmp}"/all.po "${target}" || return 1
		msgen -o "${tmp}"/old.po "${tmp}"/all.po || return 1
		# Messages defined only once, and of those, the ones from the tarball #
		msgcat --less-than=2 -o "${tmp}"/unique.po "${tmp}"/new.po "${tmp}"/old.po || return 1
		[[ -f ${tmp}/unique.po ]] || continue
		msgcomm --more-than=1 -o "${tmp}"/add.po "${tmp}"/unique.po "${tmp}"/new.po || return 1
		[[ -f ${tmp}/add.po ]] || continue
		# Without the header entry #
		body=$(awk 'BEGIN { RS = ""; ORS = "\n\n" } NR > 1' "${tmp}"/add.po)
		[[ -z ${body} ]] || printf '\n%s\n' "${body}" >> "${target}"
	done
	rm -rf "${tmp}"
}

## Print only the added and removed lines of a diff on stdin, so that the
##  hash of a change does not depend on its context.
changed_lines() {
	grep -a '^[+-]' | grep -av '^\(+++\|---\) ' || true
}

## Print the git commit of repository $1, with -dirty if the paths $2... (or
##  any path, if none are given) have uncommitted changes.
git_commit() {
	local repo=$1 commit
	shift
	commit=$(git -c safe.directory='*' -C "${repo}" rev-parse HEAD 2>/dev/null) || { echo "unknown"; return; }
	[[ -n $(git -c safe.directory='*' -C "${repo}" status --porcelain -- "$@" 2>/dev/null) ]] && commit+="-dirty"
	echo "${commit}"
}

## Versioned ehooks directories, as the overlay looks them up (docs/ehooks.md):
##  for OVERLAY_PKG="ehooks/www-client/firefox:rapid", the overlay uses
##  firefox-160:rapid (or firefox-160.0:rapid, firefox-160) for Firefox 160 and
##  firefox:rapid for the other versions. An OVERLAY_PKG that already names a
##  version (ehooks/mail-client/thunderbird-153) is used as it is.

## Print the name and the slot (":rapid" or nothing) of the OVERLAY_PKG that the
##  loaded package declares, or fail if it cannot have versioned directories.
ehooks_name_slot() {
	local declared=${OVERLAY_PKG_DECLARED:-${OVERLAY_PKG:-}} name slot=
	name=${declared%%:*}
	[[ ${declared} == *:* ]] && slot=":${declared#*:}"
	[[ ${declared} == ehooks/* && ! ${name##*/} =~ -[0-9][0-9.]*$ ]] || return 1
	echo "${name} ${slot}"
}

## Print the versioned ehooks directories of the loaded package ($1: the
##  overlay directory), relative to it and sorted.
versioned_ehooks_dirs() {
	local overlay=$1 name slot dir
	read -r name slot < <(ehooks_name_slot) || return 0
	for dir in "${overlay}/${name}"-[0-9]*; do
		[[ -d ${dir} ]] || continue
		dir=${dir#"${overlay}"/}
		[[ ${dir#"${name}"} =~ ^-[0-9][0-9.]*(${slot})?$ ]] && echo "${dir}"
	done | LC_ALL=C sort
}

## Set OVERLAY_PKG of the loaded package to the most specific ehooks directory
##  for the upstream part of version $2 ($1: the overlay directory), in the
##  order of the overlay: firefox-160.0.1:rapid, firefox-160.0.1, ...,
##  firefox-160:rapid, firefox-160, then the declared OVERLAY_PKG. The declared
##  one stays in OVERLAY_PKG_DECLARED for the input hash.
resolve_overlay_pkg() {
	local overlay=$1 version=${2#*:} name slot candidate
	OVERLAY_PKG_DECLARED=${OVERLAY_PKG_DECLARED:-${OVERLAY_PKG:-}}
	read -r name slot < <(ehooks_name_slot) || return 0
	[[ ${version} =~ ^[0-9]+(\.[0-9]+)* ]] || return 0
	version=${BASH_REMATCH[0]}
	while [[ -n ${version} ]]; do
		for candidate in "${name}-${version}${slot}" "${name}-${version}"; do
			if [[ -d ${overlay}/${candidate} ]]; then
				OVERLAY_PKG=${candidate}
				return 0
			fi
		done
		if [[ ${version} == *.* ]]; then
			version=${version%.*}
		else
			version=
		fi
	done
}

## Print the input hash of a loaded package ($1: the overlay directory). It
##  covers everything the build uses besides the Ubuntu source. A package whose
##  input hash and Ubuntu version match the staging PPA is not built again.
input_hash() {
	local overlay=$1
	{
		echo "format ${FORMAT_VERSION}"
		(cd "${PKG_DIR}" && find . -type f -print0 | sort -z | xargs -0 sha256sum)
		local declared=${OVERLAY_PKG_DECLARED:-${OVERLAY_PKG:-}} dir
		if [[ -n ${declared} && -d ${overlay}/${declared}/files ]]; then
			(cd "${overlay}/${declared}"/files && find . -type f -print0 | sort -z | xargs -0 sha256sum)
		fi
		## The versioned ehooks directories that resolve_overlay_pkg may pick. A new
		##  or changed one changes the input hash, so the package is built again.
		while read -r dir; do
			echo "${dir}"
			if [[ -d ${overlay}/${dir}/files ]]; then
				(cd "${overlay}/${dir}"/files && find . -type f -print0 | sort -z | xargs -0 sha256sum)
			fi
		done < <(versioned_ehooks_dirs "${overlay}")
		if [[ ${#OVERLAY_FILES[@]} -gt 0 ]]; then
			(cd "${overlay}" && sha256sum "${OVERLAY_FILES[@]}")
		fi
		if [[ -d ${REPO_ROOT}/branding ]]; then
			(cd "${REPO_ROOT}"/branding && find . -type f -print0 | sort -z | xargs -0 -r sha256sum)
		fi
	} | sha256sum | cut -c1-32
}

## List all packages: the ports in packages/ and the own packages in local/.
list_packages() {
	local dir
	for dir in "${REPO_ROOT}"/packages/*/package.sh "${REPO_ROOT}"/local/*/package.sh; do
		[[ -f ${dir} ]] || continue
		dir=${dir%/package.sh}
		echo "${dir##*/}"
	done
}

## Load the port packages/$1/package.sh or the own package local/$1/package.sh
##  into the current shell. For an own package, LOCAL=1 is set, and its source
##  is the rest of local/$1.
load_package() {
	local pkg=$1 file

	unset OVERLAY_PKG OVERLAY_PKG_DECLARED UBUNTU_SRC UBUNTU_SERIES DEBIAN_SUITE SOURCE_NAME GROUP PATCH_MODE LOCAL HOLD
	PATCHES=()
	OVERLAY_FILES=()
	unset -f debian_edit src_edit local_prepare

	if [[ -f ${REPO_ROOT}/local/${pkg}/package.sh ]]; then
		PKG_DIR="${REPO_ROOT}/local/${pkg}"
		file="${PKG_DIR}/package.sh"
		source "${file}"
		LOCAL=1
		SOURCE_NAME=${pkg}
		PATCH_MODE=direct
		return
	fi

	PKG_DIR="${REPO_ROOT}/packages/${pkg}"
	file="${PKG_DIR}/package.sh"
	[[ -f ${file} ]] || die "Package ${pkg} not found in packages/ or local/."
	source "${file}"

	[[ -n ${OVERLAY_PKG} ]] || die "${file}: OVERLAY_PKG is not set."
	[[ -n ${UBUNTU_SRC} ]] || die "${file}: UBUNTU_SRC is not set."
	SOURCE_NAME=${SOURCE_NAME:-${UBUNTU_SRC}}
}
