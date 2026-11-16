OVERLAY_PKG="ehooks/gnome-extra/nm-applet"
UBUNTU_SRC="network-manager-applet"
GROUP="desktop"

## Ubuntu already applies Have-the-appindicator-enabled-by-default.patch.
PATCHES=(
	do-not-warn-about-deprecated-appindicator.patch
	show-notifications-via-libnotify-when-in-unity.patch
)

debian_edit() {
	# libnotify notifications in Unity (show-notifications-via-libnotify-when-in-unity.patch) #
	sed -i -e "/^ *libnma-dev /a \               libnotify-dev (>= 0.7)," debian/control || return 1
	grep -Fq "               libnotify-dev (>= 0.7)," debian/control || return 1
}
