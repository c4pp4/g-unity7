OVERLAY_PKG="unity-indicators/indicator-messages"
UBUNTU_SRC="indicator-messages"

## X-GNOME-HiddenUnderSystemd of the ebuild, the other changes concern Gentoo
##  (tests, gtk-doc, SYSTEMD_USERDIR). Ubuntu builds it with systemd-dev, the
##  systemd user unit is installed.

src_edit() {
	# Started by the systemd user unit (unity-panel-service.service.wants of #
	#  unity-services) when cinnamon-session runs as a systemd service #
	echo "X-GNOME-HiddenUnderSystemd=true" >> data/indicator-messages.desktop.in || return 1
	grep -qx "X-GNOME-HiddenUnderSystemd=true" data/indicator-messages.desktop.in || return 1
}
