OVERLAY_PKG="x11-misc/notify-osd"
UBUNTU_SRC="notify-osd"
GROUP="desktop"

## The XDG autostart file of the ebuild, the other changes concern Gentoo
##  (tests, savedconfig). Debian does not install the D-Bus activation file
##  either (#640120).

debian_edit() {
	# Started from XDG autostart in Unity and restarted if it exits, as in the #
	#  ebuild (Ubuntu disables the autostart, nothing started notify-osd in the #
	#  Unity session) #
	sed -i \
		-e "/^NotShowIn=/d" \
		-e "/^X-GNOME-Autostart-enabled=/d" \
		debian/notify-osd.desktop || return 1
	! grep -q "^NotShowIn=\|Autostart-enabled" debian/notify-osd.desktop || return 1
	printf '%s\n' "OnlyShowIn=Unity;" "NoDisplay=true" "X-GNOME-AutoRestart=true" \
		>> debian/notify-osd.desktop || return 1
	grep -qx "X-GNOME-AutoRestart=true" debian/notify-osd.desktop || return 1
}
