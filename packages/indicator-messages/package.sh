OVERLAY_PKG="unity-indicators/indicator-messages"
UBUNTU_SRC="indicator-messages"

## The ebuild's X-GNOME-HiddenUnderSystemd. The other changes only concern
##  Gentoo (tests, gtk-doc, SYSTEMD_USERDIR). Ubuntu builds it with
##  systemd-dev, so the systemd user unit is installed.

src_edit() {
	# The systemd user unit starts it through unity-services' #
	#  unity-panel-service.service.wants when cinnamon-session runs as a #
	#  systemd service #
	echo "X-GNOME-HiddenUnderSystemd=true" >> data/indicator-messages.desktop.in || return 1
	grep -qx "X-GNOME-HiddenUnderSystemd=true" data/indicator-messages.desktop.in || return 1
}
