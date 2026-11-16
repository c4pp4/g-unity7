OVERLAY_PKG="unity-indicators/indicator-keyboard"
UBUNTU_SRC="indicator-keyboard"
GROUP="desktop"

PATCHES=(
	optional-fcitx.patch
	Prevent-segfault-by-obtaining-style-context-associated-to-widget.patch
	Handle-SIGTERM-in-the-main-loop.patch
)

debian_edit() {
	# Install the systemd user unit, as SYSTEMD_USERDIR in the ebuild does. #
	#  systemd.pc is in systemd-dev. Without it, configure found no #
	#  SYSTEMD_USERDIR and the unit was not installed, so nothing started the #
	#  indicator: unity-services' unity-panel-service.service.wants link pointed #
	#  to a missing unit #
	sed -i -e "s/^\( *\)systemd,$/&\n\1systemd-dev,/" debian/control || return 1
	grep -q "^ *systemd-dev,$" debian/control || return 1

	# Without Fcitx 4, as the ebuild (optional-fcitx.patch, --disable-fcitx). #
	#  The libraries of Fcitx 4 suggest fcitx, which apt then keeps with the #
	#  KDE Frameworks that it pulls in, although G Unity⁷ uses IBus #
	sed -i \
		-e "/^ *fcitx-libs-dev (>= 1:4.2.8.3),$/d" \
		-e "/^ *gir1.2-fcitx-1.0,$/d" \
		debian/control || return 1
	! grep -q "fcitx" debian/control || return 1
	printf '\n%s\n\t%s\n' \
		"override_dh_auto_configure:" \
		"dh_auto_configure -- --disable-fcitx" \
		>> debian/rules || return 1
	grep -Pqx "\tdh_auto_configure -- --disable-fcitx" debian/rules || return 1
}
