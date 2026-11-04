OVERLAY_PKG="unity-indicators/indicator-session"
UBUNTU_SRC="indicator-session"
GROUP="desktop"

## The help of Unity (USE help of the ebuild) and the CMake version, the other
##  changes of the ebuild concern Gentoo (sandbox, whoopsie, elogind).

debian_edit() {
	# The help of Unity (help:ubuntu-help) is in unity-docs #
	sed -i -e "s/^\( *\)yelp,$/&\n\1unity-docs,/" debian/control || return 1
	grep -q "^ *unity-docs,$" debian/control || return 1

	# Unity Help in the Dash, as the ebuild installs it #
	install -d debian/g-unity7 || return 1
	install -m 644 "${FILESDIR}"/unity-yelp.desktop debian/g-unity7/ || return 1
	# The translations are in g-unity7-l10n (unity-help), the language packs of Ubuntu #
	#  install indicator-session without them and take precedence #
	sed -i -e "s/^X-GNOME-Gettext-Domain=indicator-session$/X-GNOME-Gettext-Domain=unity-help/" \
		debian/g-unity7/unity-yelp.desktop || return 1
	grep -qx "X-GNOME-Gettext-Domain=unity-help" debian/g-unity7/unity-yelp.desktop || return 1
	echo "debian/g-unity7/unity-yelp.desktop usr/share/applications/" > debian/indicator-session.install || return 1
}

src_edit() {
	# CMake 4 does not support a minimum version older than 3.5 #
	sed -i "/cmake_minimum_required/{s/2\.8\.9/3.10/}" CMakeLists.txt || return 1
	grep -q "cmake_minimum_required.*3\.10" CMakeLists.txt || return 1

	# Unity Help… in the menu, opening the help of Unity instead of gnome-help #
	sed -i \
		-e 's:distro_name = g_strdup(value):distro_name = g_strdup("Unity"):' \
		src/service.c || return 1
	grep -Fq 'distro_name = g_strdup("Unity")' src/service.c || return 1
	sed -i \
		-e 's:run_outside_app ("yelp");:run_outside_app ("yelp help\:ubuntu-help");:' \
		src/backend-dbus/actions.c || return 1
	grep -Fq 'run_outside_app ("yelp help:ubuntu-help");' src/backend-dbus/actions.c || return 1
	grep -Fq 'run_outside_app ("yelp help:mate-user-guide");' src/backend-dbus/actions.c || return 1
}
