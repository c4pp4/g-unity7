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

## Print the first 12 hex digits of the sha256 of stdin.
short_hash() {
	sha256sum | cut -c1-12
}

## True if the source tree $1 has a patch in debian/patches/series (a series
##  file with only an empty line or comments has none, quilt fails on it).
has_patches() {
	grep -q '^[^#[:space:]]' "$1"/debian/patches/series 2>/dev/null
}

## For src_edit: merge the po files of a tarball ($1, po/*.po) into the po files
##  of the source in the current directory as "msgcat --use-first" of the ehooks
##  does, but only append the messages the source does not have, so that the
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
		# Every message of the source counts as a definition, also a fuzzy, #
		#  an untranslated (msgcat does not count them) and an obsolete one #
		#  (msgfmt of gettext 1.0 rejects an active duplicate of it) #
		msgattrib --clear-obsolete --clear-fuzzy -o "${tmp}"/all.po "${target}" || return 1
		msgen -o "${tmp}"/old.po "${tmp}"/all.po || return 1
		# The messages defined only once, of them the ones of the tarball #
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

## Print the git commit of a repository ($1), with -dirty for uncommitted
##  changes in the paths $2... (all paths without them).
git_commit() {
	local repo=$1 commit
	shift
	commit=$(git -c safe.directory='*' -C "${repo}" rev-parse HEAD 2>/dev/null) || { echo "unknown"; return; }
	[[ -n $(git -c safe.directory='*' -C "${repo}" status --porcelain -- "$@" 2>/dev/null) ]] && commit+="-dirty"
	echo "${commit}"
}

## Print the input hash of a loaded package ($1: overlay directory): what its
##  build is made from besides the Ubuntu source. A package whose input hash
##  and Ubuntu version are those of the staging PPA is not built again.
input_hash() {
	local overlay=$1
	{
		echo "format ${FORMAT_VERSION}"
		(cd "${PKG_DIR}" && find . -type f -print0 | sort -z | xargs -0 sha256sum)
		if [[ -n ${OVERLAY_PKG:-} && -d ${overlay}/${OVERLAY_PKG}/files ]]; then
			(cd "${overlay}/${OVERLAY_PKG}"/files && find . -type f -print0 | sort -z | xargs -0 sha256sum)
		fi
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

## Load the port packages/$1/package.sh, or the own package local/$1/package.sh
##  (LOCAL=1, its source is the rest of local/$1), into the current shell.
load_package() {
	local pkg=$1 file

	unset OVERLAY_PKG UBUNTU_SRC UBUNTU_SERIES SOURCE_NAME GROUP PATCH_MODE LOCAL
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
