OVERLAY_PKG="unity-indicators/indicator-bluetooth"
UBUNTU_SRC="indicator-bluetooth"
GROUP="desktop"

## The systemd user unit of the ebuild, the other changes concern Gentoo
##  (empty LINGUAS, D-Bus activation file without systemd).

debian_edit() {
	# The systemd user unit: systemd.pc is in systemd-dev, without it configure #
	#  found no SYSTEMD_USERDIR and the unit was not installed (nothing started #
	#  the indicator, the unity-panel-service.service.wants link of unity-services #
	#  pointed to a missing unit), as SYSTEMD_USERDIR of the ebuild #
	sed -i -e "s/^\( *\)systemd,$/&\n\1systemd-dev,/" debian/control || return 1
	grep -q "^ *systemd-dev,$" debian/control || return 1
}
