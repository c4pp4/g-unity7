OVERLAY_PKG="ehooks/media-gfx/eog:1"
UBUNTU_SRC="eog"
GROUP="desktop"

PATCHES=(
	CUSTOM-0001-Add-a-traditional-menu-bar.patch
)

src_edit() {
	# Translations of the menu bar (CUSTOM-0001-Add-a-traditional-menu-bar.patch) #
	merge_translations "${FILESDIR}"/global-menu-translations-xenial.tar.xz || return 1
}
