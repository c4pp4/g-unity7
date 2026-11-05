OVERLAY_PKG="unity-indicators/indicator-application"
UBUNTU_SRC="indicator-application"
GROUP="desktop"

## The systemd user unit and X-GNOME-HiddenUnderSystemd of the ebuild, the
##  other changes concern Gentoo (upstart paths).

debian_edit() {
	# The systemd user unit: systemd.pc is in systemd-dev, without it configure #
	#  found no SYSTEMD_USERDIR and the unit was not installed (the indicator ran #
	#  from XDG autostart only, the unity-panel-service.service.wants link of #
	#  unity-services pointed to a missing unit), as SYSTEMD_USERDIR of the ebuild #
	sed -i -e "s/^\( *\)systemd,$/&\n\1systemd-dev,/" debian/control || return 1
	grep -q "^ *systemd-dev,$" debian/control || return 1
}

src_edit() {
	# Started by the systemd user unit when cinnamon-session runs as a systemd service #
	echo "X-GNOME-HiddenUnderSystemd=true" >> data/indicator-application.desktop.in || return 1
	grep -qx "X-GNOME-HiddenUnderSystemd=true" data/indicator-application.desktop.in || return 1
}
