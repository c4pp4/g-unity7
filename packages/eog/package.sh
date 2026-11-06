OVERLAY_PKG="ehooks/media-gfx/eog:1"
UBUNTU_SRC="eog"
GROUP="desktop"

PATCHES=(
	0001-Add-a-traditional-menu-bar.patch
)

src_edit() {
	# Menu bar translations (0001-Add-a-traditional-menu-bar.patch) #
	merge_translations "${FILESDIR}"/global-menu-translations-xenial.tar.xz || return 1
}
