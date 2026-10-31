OVERLAY_PKG="ehooks/gnome-extra/nemo"
UBUNTU_SRC="nemo"
GROUP="session"

PATCHES=(
	add-unity7-support.patch
	nemo-persist.patch
	relayout-desktop-icons-on-gtk-workareas-change.patch
)

debian_edit() {
	# Unity launcher support (add-unity7-support.patch, meson option unity-launcher) #
	sed -i \
		-e "/^ libcinnamon-desktop-dev/a \ libdbusmenu-glib-dev (>= 0.4.90)," \
		-e "/^ libx11-dev/i \ libunity-dev (>= 4.0.0)," \
		debian/control || return 1
	grep -Fq " libdbusmenu-glib-dev (>= 0.4.90)," debian/control || return 1
	grep -Fq " libunity-dev (>= 4.0.0)," debian/control || return 1

	# Archive integration with Engrampa (gnome-extra/nemo-engrampa) #
	sed -i -e "s/^ nemo-fileroller (>= 5.2~),$/ nemo-engrampa | nemo-fileroller (>= 5.2~),/" debian/control || return 1
	grep -Fqx " nemo-engrampa | nemo-fileroller (>= 5.2~)," debian/control || return 1

	# Hold Nemo running seamlessly in Unity (nemo-persist.patch) #
	install -d debian/g-unity7 || return 1
	install -m 644 "${FILESDIR}"/nemo-autostart.desktop.in debian/g-unity7/unity-nemo.desktop || return 1
	echo "debian/g-unity7/unity-nemo.desktop etc/xdg/autostart/" >> debian/nemo.install || return 1
	grep -Fqx "debian/g-unity7/unity-nemo.desktop etc/xdg/autostart/" debian/nemo.install || return 1
}

src_edit() {
	sed -i -e "/StartupNotify/{s/false/true/}" data/nemo.desktop.in || return 1
	grep -qx "StartupNotify=true" data/nemo.desktop.in || return 1
}
