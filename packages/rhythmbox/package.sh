OVERLAY_PKG="ehooks/media-sound/rhythmbox"
UBUNTU_SRC="rhythmbox"
GROUP="desktop"

## files/series selects the patches of the Ubuntu patchset for Gentoo, the whole
##  patchset is kept.
PATCHES=(
	unity-mediakeys-plugin.patch
)

debian_edit() {
	# The Media Player Keys plugin (unity-mediakeys-plugin.patch) #
	sed -i -e "s:^usr/lib/\*/rhythmbox/plugins/mpris$:usr/lib/*/rhythmbox/plugins/mmkeys\n&:" \
		debian/rhythmbox-plugins.install || return 1
	grep -qx "usr/lib/\*/rhythmbox/plugins/mmkeys" debian/rhythmbox-plugins.install || return 1
}

src_edit() {
	local desktop=data/org.gnome.Rhythmbox3.desktop.in

	sed -i \
		-e "s/Play\/Pause/Toggle play\/pause mode/" \
		-e "s/Stop & Quit/Quit Rhythmbox/" \
		"${desktop}" || return 1
	grep -q "^Name=Toggle play/pause mode$" "${desktop}" || return 1
	grep -q "^Name=Quit Rhythmbox$" "${desktop}" || return 1
}
