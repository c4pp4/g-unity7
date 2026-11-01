OVERLAY_PKG="x11-themes/humanity-icon-theme"
UBUNTU_SRC="humanity-icon-theme"
GROUP="desktop"

src_edit() {
	# Fix unity-control-center printers panel icon #
	# 'printer' resolves to printer-symbolic of ubuntu-mono-* and Yaru-*-dark #
	# (GThemedIcon adds -symbolic fallbacks), 'printers' has no symbolic variant #
	ln -s printer.svg Humanity/devices/48/printers.svg || return 1
}
