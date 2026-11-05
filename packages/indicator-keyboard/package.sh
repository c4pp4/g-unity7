OVERLAY_PKG="unity-indicators/indicator-keyboard"
UBUNTU_SRC="indicator-keyboard"
GROUP="desktop"

PATCHES=(
	Prevent-segfault-by-obtaining-style-context-associated-to-widget.patch
	Handle-SIGTERM-in-the-main-loop.patch
)

debian_edit() {
	# The systemd user unit: systemd.pc is in systemd-dev, without it configure #
	#  found no SYSTEMD_USERDIR and the unit was not installed (nothing started #
	#  the indicator, the unity-panel-service.service.wants link of unity-services #
	#  pointed to a missing unit), as SYSTEMD_USERDIR of the ebuild #
	sed -i -e "s/^\( *\)systemd,$/&\n\1systemd-dev,/" debian/control || return 1
	grep -q "^ *systemd-dev,$" debian/control || return 1
}
