OVERLAY_PKG="unity-indicators/indicator-bluetooth"
UBUNTU_SRC="indicator-bluetooth"
GROUP="desktop"

## The ebuild's systemd user unit. The other changes only concern Gentoo
##  (empty LINGUAS, the D-Bus activation file without systemd).

debian_edit() {
	# Install the systemd user unit, as SYSTEMD_USERDIR in the ebuild does. #
	#  systemd.pc is in systemd-dev. Without it, configure found no #
	#  SYSTEMD_USERDIR and the unit was not installed, so nothing started the #
	#  indicator: unity-services' unity-panel-service.service.wants link pointed #
	#  to a missing unit #
	sed -i -e "s/^\( *\)systemd,$/&\n\1systemd-dev,/" debian/control || return 1
	grep -q "^ *systemd-dev,$" debian/control || return 1
}
