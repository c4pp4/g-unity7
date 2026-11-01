OVERLAY_PKG="net-mail/mailnag"
UBUNTU_SRC="mailnag"
GROUP="desktop"

PATCHES=(
	handle-glib-exception-in-conntest.patch
	fix-notification-icon.patch
	replace-removed-imp-module.patch
)

src_edit() {
	# If a .desktop file does not have inline #
	# translations, fall back to calling gettext #
	echo "X-GNOME-Gettext-Domain=mailnag" >> data/mailnag-config.desktop || return 1
	grep -qx "X-GNOME-Gettext-Domain=mailnag" data/mailnag-config.desktop || return 1
}
