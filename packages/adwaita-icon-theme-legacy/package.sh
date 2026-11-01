OVERLAY_PKG="ehooks/x11-themes/adwaita-icon-theme-legacy"
UBUNTU_SRC="adwaita-icon-theme-legacy"

src_edit() {
	# Inherit Adwaita icons before hicolor #
	sed -i \
		-e "s/Inherits=/Inherits=Adwaita,/" \
		index.theme || return 1
	grep -q "^Inherits=Adwaita," index.theme || return 1
}
