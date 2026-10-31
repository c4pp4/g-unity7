OVERLAY_PKG="x11-themes/yaru-theme"
GROUP="desktop"
UBUNTU_SRC="yaru-theme"

## The default USE flags of the ebuild: +unity.
PATCHES=(
	Remove-light-edges-in-menu-corners.patch
)

debian_edit() {
	# Yaru-dark drop-down menu icon as "go-down-symbolic" for all dark accents #
	install -d debian/g-unity7 || return 1
	install -m 644 "${FILESDIR}"/go-down-icon/Yaru-dark/scalable/actions/go-down-symbolic.svg debian/g-unity7/ || return 1
	printf '\n%s\n\t%s\n\t%s\n' \
		"execute_after_dh_install:" \
		"install -D -m 644 debian/g-unity7/go-down-symbolic.svg debian/yaru-theme-icon/usr/share/icons/Yaru-dark/scalable/actions/go-down-symbolic.svg" \
		'for d in debian/yaru-theme-icon/usr/share/icons/Yaru-*-dark; do mkdir -p $$d/scalable/actions && ln -sf ../../../Yaru-dark/scalable/actions/go-down-symbolic.svg $$d/scalable/actions/go-down-symbolic.svg; done' \
		>> debian/rules || return 1
	grep -Pq "^\tinstall -D -m 644 debian/g-unity7/go-down-symbolic.svg " debian/rules || return 1
}

src_edit() {
	## Don't set window's title bar name alignment ##
	## to center, it prevents title bar name from being ##
	## partially cropped by window's title bar menu ##
	sed -i \
		-e "/UnityDecoration-title-indent/{s/0px/10px/}" \
		-e "/UnityDecoration-title-alignment/d" \
		gtk/src/default/gtk-3.0/apps/_unity7.scss || return 1
	grep -q "UnityDecoration-title-indent: *10px" gtk/src/default/gtk-3.0/apps/_unity7.scss || return 1
	! grep -Fq "UnityDecoration-title-alignment" gtk/src/default/gtk-3.0/apps/_unity7.scss || return 1

	## Tweak mate-terminal ##
	cat "${FILESDIR}"/mate-terminal.css >> \
		gtk/src/default/gtk-3.0/apps/_mate-terminal.scss || return 1

	## Tweak nemo ##
	cat "${FILESDIR}"/nemo.css >> \
		gtk/src/default/gtk-3.0/apps/_nemo.scss || return 1

	## Add Bark and Viridian accent colors ##
	sed -i \
		-e "/value: \[/a 'bark',\n'viridian'," \
		meson_options.txt || return 1
	grep -qx "'viridian'," meson_options.txt || return 1

	## Add Humanity to Inherits (index.theme) ##
	sed -i \
		-e "s/hicolor'/hicolor', 'Humanity'/" \
		icons/src/generate-index-theme.py || return 1
	grep -Fq "hicolor', 'Humanity'" icons/src/generate-index-theme.py || return 1
}
