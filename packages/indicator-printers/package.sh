OVERLAY_PKG="unity-indicators/indicator-printers"
UBUNTU_SRC="indicator-printers"
GROUP="desktop"

## The ebuild's systemd user unit. The other changes only concern Gentoo
##  (the upstart session, XDG autostart without the unit).

debian_edit() {
	# Install the systemd user unit, as SYSTEMD_USERDIR in the ebuild does. #
	#  systemd.pc is in systemd-dev. Without it, configure found no #
	#  SYSTEMD_USERDIR and the unit was not installed, so nothing started the #
	#  indicator: unity-services' unity-panel-service.service.wants link pointed #
	#  to a missing unit #
	sed -i -e "s/^\( *\)systemd,$/&\n\1systemd-dev,/" debian/control || return 1
	grep -q "^ *systemd-dev,$" debian/control || return 1
}
