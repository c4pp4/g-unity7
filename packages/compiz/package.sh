OVERLAY_PKG="unity-base/compiz"
UBUNTU_SRC="compiz"
GROUP="desktop"

PATCHES=(
	compizconfig-fix-spurious-errors.patch
)

debian_edit() {
	# Fix Expo y-offset and y-bottom-offset #
	echo -e \
		"\n[org.compiz.expo]\ny-offset = 35\ny-bottom-offset = 5" \
		>> debian/compiz-gnome.gsettings-override || return 1
	grep -Fqx "y-bottom-offset = 5" debian/compiz-gnome.gsettings-override || return 1
}

src_edit() {
	# Fix desktop freeze for Chromium, Chrome and Kodi when returning #
	#  from fullscreen video when using proprietary gfx drivers #
	#  Related to Composite plugin - Unredirect Match, see https://askubuntu.com/questions/577459
	sed -i \
		-e 's:!(class=chromium-browser):!(class=chromium-browser) \&amp; !(class=Chromium-browser-chromium) \&amp; !(class=Google-chrome) \&amp; !(class=Kodi):' \
		plugins/composite/composite.xml.in || return 1
	grep -Fq '!(class=Kodi)' plugins/composite/composite.xml.in || return 1
}
