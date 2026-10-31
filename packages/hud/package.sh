OVERLAY_PKG="unity-base/hud"
UBUNTU_SRC="hud"
GROUP="desktop"

## Qt 6 as in the overlay, with dee-qt6, libdbusmenu-qt6 (packages of the PPA)
##  and gsettings-qt6 of Ubuntu. The tests are disabled as by the default USE
##  flags of the ebuild (-test), so the Qt 6 libqtdbustest and libqtdbusmock
##  are not needed.
PATCHES=(
	Qt6-migration.patch
)

debian_edit() {
	sed -i \
		-e "s/\(^\|[ :]\)cmake (>= 3.4),$/\1cmake (>= 3.16),/" \
		-e "s/^\( *\)libdbusmenu-qt5-dev (>= 0.9.3),$/\1libdbusmenu-qt6-dev (>= 0.9.3+16.04.20160218-5+gu7),/" \
		-e "s/^\( *\)libdee-qt5-dev,$/\1libdee-qt6-dev (>= 3.3+14.04.20140317-0ubuntu9+gu7),/" \
		-e "s/^\( *\)libgsettings-qt-dev,$/\1libgsettings-qt6-dev,/" \
		-e "s/^\( *\)libqt5sql5-sqlite\(,\?\)$/\1libqt6sql6-sqlite\2/" \
		-e "s/^\( *\)qtbase5-dev,$/\1qt6-base-dev,/" \
		-e "/^ *libqtdbustest1-dev /d" \
		-e "/^ *libqtdbusmock1-dev /d" \
		-e "/^ *qtdbustest-runner,$/d" \
		-e "s/^\( *\)systemd,$/\1systemd-dev,/" \
		debian/control || return 1
	# systemd.pc (the systemd user unit dir) is in systemd-dev #
	grep -q "^ *systemd-dev,$" debian/control || return 1
	! grep -q "qt5\|libqtdbus\|qtdbustest" debian/control || return 1
	grep -q "^ *libdee-qt6-dev (>= " debian/control || return 1
	grep -Fq "cmake (>= 3.16)," debian/control || return 1
	grep -q "^ *libdbusmenu-qt6-dev (>= " debian/control || return 1

	# The Qt 6 symbols of libhud-client2 differ from the Qt 5 ones, only the #
	#  packages of hud use the library #
	rm debian/libhud-client2.symbols || return 1

	sed -i \
		-e "s/^\tdh_auto_configure -- /&-DENABLE_TESTS=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.16 /" \
		debian/rules || return 1
	grep -Fq -- "-DENABLE_TESTS=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.16 " debian/rules || return 1
}

src_edit() {
	# Fix Python 3 incompatibilities #
	sed -i \
		-e '/except /{s/,/ as/}' \
		-e 's/^import po$/from hudkeywords import po/' \
		-e 's/action="count", help/action="count", default=0, help/' \
		tools/hudkeywords/hudkeywords/cli.py || return 1
	grep -Fqx "from hudkeywords import po" tools/hudkeywords/hudkeywords/cli.py || return 1
	grep -Fq 'action="count", default=0, help' tools/hudkeywords/hudkeywords/cli.py || return 1

	# Remove unsupported setuptools option #
	sed -i '/test_suite/d' tools/hudkeywords/setup.py || return 1

	# Remove invalid attribute #
	sed -i 's/ visible="0"//' tools-vala/hud-gtk.ui || return 1
	! grep -Fq ' visible="0"' tools-vala/hud-gtk.ui || return 1

	# Don't try to find test deps #
	sed -i \
		-e '/QTDBUSTEST/d' \
		-e '/QTDBUSMOCK/d' \
		CMakeLists.txt || return 1
}
