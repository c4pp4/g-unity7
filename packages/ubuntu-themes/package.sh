OVERLAY_PKG="x11-themes/ubuntu-themes"
UBUNTU_SRC="ubuntu-themes"

src_edit() {
	## Add nemo nautilus-like theme ##
	cat "${FILESDIR}"/nemo.css >> \
		Ambiance/gtk-3.20/apps/nemo.css || return 1

	## Add widget fixes ##
	cat "${FILESDIR}"/gtk-widgets.css >> \
		Ambiance/gtk-3.20/gtk-widgets.css || return 1

	## Add customized drop-down menu icon as "go-down-symbolic", ##
	##   the one from Adwaita theme is too dark since v3.30 ##
	cp -r "${FILESDIR}"/go-down-icon/. . || return 1

	## Add Ambiance indicator-notifications icons ##
	cp -r "${FILESDIR}"/indicator-notifications/. . || return 1
	[[ -f ubuntu-mono-dark/apps/22/indicator-notification-read.svg ]] || return 1
}
