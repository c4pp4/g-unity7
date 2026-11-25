OVERLAY_PKG="ehooks/net-p2p/transmission"
UBUNTU_SRC="transmission"
GROUP="desktop"

## In the order of the ehook. The default WITH_APPINDICATOR=AUTO enables the tray
##  icon of add-appindicator-support.patch, with libdbusmenu-glib from
##  libayatana-appindicator3-dev.
PATCHES=(
	add-appindicator-support.patch
	add-global-menu-support.patch
)

debian_edit() {
	# 02-pre_pkg_preinst.ehooks: remove StartupWMClass from the installed desktop #
	#  file. Since 4.1.4 it is the Wayland app ID, which does not match the X11 #
	#  window class, so bamf does not match the window #
	! grep -q '^execute_before_dh_install:' debian/rules || return 1
	printf '\n%s\n%s\n\t%s\n' \
		"# G Unity⁷: StartupWMClass (the Wayland app ID since 4.1.4) does not match the X11 window class" \
		"execute_before_dh_install:" \
		"sed -i -e '/^StartupWMClass=/d' debian/tmp/usr/share/applications/transmission-gtk.desktop" \
		>> debian/rules || return 1
	grep -Fqx "$(printf '\t')sed -i -e '/^StartupWMClass=/d' debian/tmp/usr/share/applications/transmission-gtk.desktop" \
		debian/rules || return 1
}
