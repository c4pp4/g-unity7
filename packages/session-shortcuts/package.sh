OVERLAY_PKG="unity-base/session-shortcuts"
UBUNTU_SRC="session-shortcuts"
GROUP="desktop"

## The translations are in g-unity7-l10n (no language pack of Ubuntu has them).

debian_edit() {
	# unity-session-quit of unity-session instead of gnome-session-quit #
	sed -i -e "s/^\( *\)gnome-session-bin,$/\1unity-session (>= 49.4+gu7.5~),/" debian/control || return 1
	grep -q "^ *unity-session (>= 49.4+gu7.5~),$" debian/control || return 1
	! grep -q "gnome-session" debian/control || return 1
}

src_edit() {
	# The dialogs of Unity, gnome-session-quit is not installed (the session #
	#  manager is cinnamon-session) #
	sed -i -e "s/gnome-session-quit/unity-session-quit/" *.desktop.in || return 1
	! grep -q "gnome-session-quit" *.desktop.in || return 1
	grep -qx "Exec=unity-session-quit --power-off" shutdown.desktop.in || return 1
}
