OVERLAY_PKG="gnome-extra/activity-log-manager"
UBUNTU_SRC="activity-log-manager"
GROUP="desktop"

PATCHES=(
	remove-dash-online-search-tab.patch
)

debian_edit() {
	# Fix build with GCC 15 (incompatible pointer types are errors, as in unity-control-center of Ubuntu) #
	sed -i -e "/^#!\/usr\/bin\/make -f$/a \\\nexport DEB_CFLAGS_MAINT_APPEND = -Wno-error=incompatible-pointer-types" debian/rules || return 1
	grep -qx "export DEB_CFLAGS_MAINT_APPEND = -Wno-error=incompatible-pointer-types" debian/rules || return 1
}

src_edit() {
	# Don't resize record switch #
	sed -i \
		"/record_button = new Switch();/a record_button.valign = Gtk.Align.CENTER;" \
		src/unified-privacy.vala || return 1
	grep -Fq "record_button.valign = Gtk.Align.CENTER;" src/unified-privacy.vala || return 1
}
