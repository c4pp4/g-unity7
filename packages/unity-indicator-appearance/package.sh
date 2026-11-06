OVERLAY_PKG="unity-indicators/indicator-appearance"
UBUNTU_SRC="unity-indicator-appearance"
GROUP="desktop"

PATCHES=(
	Add-more-accent-colors.patch
	Add-translation-support.patch
	Update-status-on-icon-theme-change.patch
	Remove-unused-libnotify.patch
)

debian_edit() {
	# Yaru panel icons (Add-more-accent-colors.patch) #
	install -d debian/g-unity7 || return 1
	cp -r "${FILESDIR}"/icons debian/g-unity7/ || return 1
	sed -i -e "\$a debian/g-unity7/icons /usr/share/" debian/install || return 1
	grep -Fqx "debian/g-unity7/icons /usr/share/" debian/install || return 1

	# Notifications are never sent (Remove-unused-libnotify.patch) #
	sed -i -e "/^Depends:/{s/, gir1.2-notify-0.7//}" debian/control || return 1
	! grep -Fq "gir1.2-notify-0.7" debian/control || return 1
}

src_edit() {
	# If a .desktop file does not have inline #
	# translations, fall back to calling gettext #
	sed -i -e "\$a X-GNOME-Gettext-Domain=indicator-appearance" autostart/unity-indicator-appearance.desktop || return 1
	grep -qx "X-GNOME-Gettext-Domain=indicator-appearance" autostart/unity-indicator-appearance.desktop || return 1
}
