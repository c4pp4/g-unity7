OVERLAY_PKG="unity-indicators/indicator-application"
UBUNTU_SRC="indicator-application"
GROUP="desktop"

## The ebuild's systemd user unit and X-GNOME-HiddenUnderSystemd. The other
##  changes only concern Gentoo (upstart paths).

debian_edit() {
	# Install the systemd user unit, as SYSTEMD_USERDIR in the ebuild does. #
	#  systemd.pc is in systemd-dev. Without it, configure found no #
	#  SYSTEMD_USERDIR and the unit was not installed. The indicator then ran #
	#  only from XDG autostart, and unity-services' #
	#  unity-panel-service.service.wants link pointed to a missing unit #
	sed -i -e "s/^\( *\)systemd,$/&\n\1systemd-dev,/" debian/control || return 1
	grep -q "^ *systemd-dev,$" debian/control || return 1
}

src_edit() {
	# The systemd user unit starts it when cinnamon-session runs as a systemd service #
	echo "X-GNOME-HiddenUnderSystemd=true" >> data/indicator-application.desktop.in || return 1
	grep -qx "X-GNOME-HiddenUnderSystemd=true" data/indicator-application.desktop.in || return 1
}
