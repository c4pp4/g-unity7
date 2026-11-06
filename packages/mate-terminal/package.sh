OVERLAY_PKG="ehooks/x11-terms/mate-terminal"
UBUNTU_SRC="mate-terminal"
GROUP="desktop"

## add-unity-list.patch in packages/mate-terminal/patches is a variant, because
##  Ubuntu's desktop file does not end with an empty line.
PATCHES=(
	add-terminal-screen-style-class.patch
	add-unity-list.patch
	scrollbar-background-theming.patch
)

debian_edit() {
	# Unity defaults: the terminal for Nemo and the Unity shortcut, and a transparent background #
	install -d debian/g-unity7 || return 1
	install -m 644 "${FILESDIR}"/unity-mate-terminal.gsettings-override \
		debian/g-unity7/10_unity-mate-terminal.gschema.override || return 1
	sed -i -e "\$a debian/g-unity7/10_unity-mate-terminal.gschema.override usr/share/glib-2.0/schemas/" \
		debian/mate-terminal.install || return 1
	grep -Fqx "debian/g-unity7/10_unity-mate-terminal.gschema.override usr/share/glib-2.0/schemas/" \
		debian/mate-terminal.install || return 1
}
