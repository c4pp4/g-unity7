OVERLAY_PKG="gnome-extra/activity-log-manager"
UBUNTU_SRC="activity-log-manager"
GROUP="desktop"

## diagnostics-chain-up-dispose.patch is only for Ubuntu. It fixes the
##  whoopsie Diagnostics page, which Gentoo builds without.
PATCHES=(
	remove-dash-online-search-tab.patch
	diagnostics-chain-up-dispose.patch
)

debian_edit() {
	# Fix the build with GCC 15, which makes incompatible pointer types errors, as Ubuntu's unity-control-center does #
	sed -i -e "/^#!\/usr\/bin\/make -f$/a \\\nexport DEB_CFLAGS_MAINT_APPEND = -Wno-error=incompatible-pointer-types" debian/rules || return 1
	grep -qx "export DEB_CFLAGS_MAINT_APPEND = -Wno-error=incompatible-pointer-types" debian/rules || return 1
}

src_edit() {
	# Don't resize record switch #
	sed -i \
		"/record_button = new Switch();/a record_button.valign = Gtk.Align.CENTER;" \
		src/unified-privacy.vala || return 1
	grep -Fq "record_button.valign = Gtk.Align.CENTER;" src/unified-privacy.vala || return 1

	# Fix the LOCALE_DIR, THEME_DIR and PKG_DATA_DIR prefix, as the ebuild fixes #
	#  config.h. PREFIX is not set and DATADIRNAME is set only later, so the #
	#  unity-control-center panel looked for its translations in //locale #
	sed -i -e 's:"${PREFIX}/${DATADIRNAME}/:"/usr/share/:' configure.ac || return 1
	grep -Fq 'AC_DEFINE_UNQUOTED(LOCALE_DIR, "/usr/share/locale",' configure.ac || return 1
	! grep -Fq '${PREFIX}/${DATADIRNAME}' configure.ac || return 1
}
